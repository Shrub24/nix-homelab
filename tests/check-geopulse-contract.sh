#!/usr/bin/env bash
set -euo pipefail

# GeoPulse runtime contract.
#
# Two digest-pinned containers replace the former source build: the native backend, which is
# bridged and reaches the cluster over the service address, and the upstream nginx UI, which
# serves the SPA, proxies the API and OSM tiles, and publishes the route's loopback listener.
# The wiring spans four places that can drift apart without any one of them failing: the route
# port, the published port, the cluster listener the backend dials, and the consumer ACL that
# admits the container supernet. This reads the evaluated configuration only — nothing here
# renders a proxy or starts a container.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "check-geopulse-contract: $*" >&2
  exit 1
}

HOST="oci-melb-1"
OTHER_HOSTS=(home-forge la-admin-1)
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

nix eval --impure --no-write-lock-file --json --expr "
let
  repo = builtins.getFlake \"path:$ROOT\";
  cfg = repo.nixosConfigurations.$HOST.config;
  containers = cfg.virtualisation.oci-containers.containers;
  backend = containers.geopulse-backend;
  ui = containers.geopulse-ui;
  route = cfg.repo.web.catalog.geopulse;
in {
  images = cfg.repo.ociImages;
  route = {
    inherit (route) upstreamPort;
    inherit (route.endpoint) port;
  };
  backend = {
    inherit (backend) image volumes extraOptions;
    environment = backend.environment;
    environmentFiles = map toString backend.environmentFiles;
  };
  ui = {
    inherit (ui) image ports extraOptions;
    environment = ui.environment;
    dependsOn = ui.dependsOn or [ ];
  };
  networkUnit = {
    exists = cfg.systemd.services ? podman-network-geopulse;
    before = cfg.systemd.services.podman-network-geopulse.before or [ ];
    execStart = cfg.systemd.services.podman-network-geopulse.serviceConfig.ExecStart or \"\";
  };
  consumer = {
    inherit (cfg.services.postgres.consumers.geopulse) allowedCIDRs password;
  };
  localEndpointPort = cfg.services.postgres.localEndpoint.port;
  serviceNetwork = {
    inherit ((import $ROOT/policy/globals.nix).serviceNetwork) address containerSourceCIDR hostName;
  };
  secrets = builtins.mapAttrs (_: s: {
    inherit (s) key restartUnits;
    path = toString (s.path or \"\");
  }) cfg.sops.secrets;
  templates = builtins.mapAttrs (_: t: {
    inherit (t) restartUnits;
    content = t.content;
  }) (cfg.sops.templates or { });
  backup = cfg.services.state-backups.services.geopulse;
  notify = builtins.attrNames cfg.services.notify.events;
  retiredUnits = {
    caddy = cfg.systemd.services ? geopulse-web;
    backend = cfg.systemd.services ? geopulse-backend;
  };
  otherHosts = builtins.mapAttrs (_: h: h.config.virtualisation.oci-containers.containers ? geopulse-ui) {
    home-forge = repo.nixosConfigurations.home-forge;
    la-admin-1 = repo.nixosConfigurations.la-admin-1;
  };
}" >"$WORK/contract.json" 2>"$WORK/contract.err" || {
  cat "$WORK/contract.err" >&2
  fail "the GeoPulse aspect does not evaluate"
}

python3 - "$WORK/contract.json" <<'PY' || fail "runtime contract violated"
import json
import re
import sys

d = json.load(open(sys.argv[1]))
errs = []
images = d["images"]
route = d["route"]
backend = d["backend"]
ui = d["ui"]
env = backend["environment"]

# The images are policy, not a second literal in the module.
if backend["image"] != images["geopulseBackend"]:
    errs.append(f"backend image {backend['image']!r} is not repo.ociImages.geopulseBackend")
if ui["image"] != images["geopulseUi"]:
    errs.append(f"ui image {ui['image']!r} is not repo.ociImages.geopulseUi")

# The route's port is the only port the UI publishes, and only on loopback.
want = [f"127.0.0.1:{route['upstreamPort']}:80"]
if ui["ports"] != want:
    errs.append(f"ui publishes {ui['ports']!r}, want {want!r} from the route's upstream port")
if route["upstreamPort"] != route["port"]:
    errs.append(f"route upstream port {route['upstreamPort']} differs from the catalog port {route['port']}")

# Both containers share the dedicated network, which exists and is ordered before them.
for name, container in (("backend", backend), ("ui", ui)):
    if "--network=geopulse" not in container["extraOptions"]:
        errs.append(f"the {name} container is not attached to the geopulse network")
if not d["networkUnit"]["exists"]:
    errs.append("the podman-network-geopulse unit is missing")
else:
    before = " ".join(d["networkUnit"]["before"])
    if "podman-geopulse-backend.service" not in before or "podman-geopulse-ui.service" not in before:
        errs.append(f"the network unit must precede both containers, got before={d['networkUnit']['before']!r}")
    if "network create" not in d["networkUnit"]["execStart"]:
        errs.append("the network unit does not create the network")
if ui["dependsOn"] != ["geopulse-backend"]:
    errs.append(f"the ui must depend on the backend container, got {ui['dependsOn']!r}")
if ui["environment"].get("GEOPULSE_BACKEND_URL") != "http://geopulse-backend:8080":
    errs.append(f"ui backend URL {ui['environment'].get('GEOPULSE_BACKEND_URL')!r} does not dial the backend by name")

# The backend is bridged, so the cluster must be dialled on the service address and the ACL
# must admit the container supernet; loopback alone leaves it unable to connect.
url = env.get("GEOPULSE_POSTGRES_URL", "")
m = re.fullmatch(r"jdbc:postgresql://host\.services\.internal:(\d+)/geopulse", url)
if not m:
    errs.append(f"backend database URL {url!r} must dial the service address, not loopback")
elif int(m.group(1)) != d["localEndpointPort"]:
    errs.append(f"backend dials port {m.group(1)}, the host's cluster is on {d['localEndpointPort']}")
sn = d["serviceNetwork"]
if sn["hostName"] in url:
    want_host = f"--add-host={sn['hostName']}:{sn['address']}"
    if want_host not in backend["extraOptions"]:
        errs.append(
            f"the backend dials {sn['hostName']} but carries no {want_host}: podman's DNS does not resolve it"
        )
cidrs = d["consumer"]["allowedCIDRs"]
if "127.0.0.1/32" not in cidrs:
    errs.append(f"consumer ACL {cidrs!r} drops loopback")
if d["serviceNetwork"]["containerSourceCIDR"] not in cidrs:
    errs.append(f"consumer ACL {cidrs!r} does not admit the container supernet: the bridged backend cannot connect")

# The password reaches the container through an environment file, never the declared env.
if "GEOPULSE_POSTGRES_PASSWORD" in env:
    errs.append("the database password must not be a container environment value")
password = d["secrets"].get("geopulse/postgres-password")
if password is None:
    errs.append("geopulse/postgres-password is not delivered")
elif password["key"] != d["consumer"]["password"]["key"]:
    errs.append(
        f"delivered password key {password['key']!r} differs from the provisioned one "
        f"{d['consumer']['password']['key']!r}: a rotation would move only one half"
    )
env_template = d["templates"].get("geopulse.env")
if env_template is None:
    errs.append("the geopulse.env template carrying the password is missing")
elif "GEOPULSE_POSTGRES_PASSWORD" not in env_template["content"]:
    errs.append("the env template does not carry GEOPULSE_POSTGRES_PASSWORD")
for name in ("geopulse/postgres-password", "geopulse/oidc-client-secret"):
    entry = d["secrets"].get(name)
    if entry and "podman-geopulse-backend.service" not in (entry["restartUnits"] or []):
        errs.append(f"{name}: a rotation must restart the backend container")

# The AI key is a read-only mount at the path the environment names.
mounts = backend["volumes"]
key_location = env.get("GEOPULSE_AI_ENCRYPTION_KEY_LOCATION", "")
if not key_location.startswith("file:"):
    errs.append(f"AI key location {key_location!r} must name a file")
else:
    inner = key_location[len("file:") :]
    want = f"{inner}:ro"
    if not any(v.endswith(want) for v in mounts):
        errs.append(f"the AI key must be mounted read-only at {inner}, got {mounts!r}")

# State is mounted and registered; the substrate export owns the database.
if not any(":/data/geopulse-backups" in v for v in mounts):
    errs.append(f"the backup directory must be mounted, got {mounts!r}")
if not any(":/data/geopulse-import" in v for v in mounts):
    errs.append(f"the import drop folder must be mounted, got {mounts!r}")
bk = d["backup"]
if not bk.get("enable"):
    errs.append("the state-backups registration is disabled")
else:
    if bk["mode"] != "live" or bk["exportPaths"]:
        errs.append(f"the registration is raw-file only, got mode {bk['mode']!r}, exports {bk['exportPaths']!r}")
    if any("/.work" in p for p in bk["paths"]):
        errs.append("the backup scratch directory must not be captured")

# Failures are notified, and nothing of the retired native runtime remains.
for unit in ("podman-geopulse-backend", "podman-geopulse-ui"):
    if unit not in d["notify"]:
        errs.append(f"{unit} must register a failure notification")
for unit, present in d["retiredUnits"].items():
    if present:
        errs.append(f"the retired {unit} unit is still defined")

# Selection is the placement.
for host, has_ui in d["otherHosts"].items():
    if has_ui:
        errs.append(f"{host} acquires a GeoPulse container without selecting the aspect")

if errs:
    print("\n".join(f"  - {e}" for e in errs), file=sys.stderr)
    sys.exit(1)
PY

echo "check-geopulse-contract: PASS (two pinned containers, service-address database dial, loopback-only publish)"
