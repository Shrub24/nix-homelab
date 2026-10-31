#!/usr/bin/env bash
# Home Assistant placement contract.
#
# What this pins is behaviour the deployment would otherwise get wrong
# silently: the container must share the host network namespace (discovery
# integrations depend on it) and publish nothing, the recorder database must be
# exported rather than copied mid-write, the crash loop must be able to reach
# `failed` so it notifies, and the route must stay withheld from the edge until
# the instance is accepted.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "check-home-assistant-contract: FAIL: $*" >&2
  exit 1
}

# Evaluation only: nothing here is decrypted or started.
cat >"$tmp/probe.nix" <<EOF
let
  repo = builtins.getFlake "path:$ROOT";
  host = c: {
    hasContainer = builtins.hasAttr "home-assistant" c.virtualisation.oci-containers.containers;
    container =
      let x = c.virtualisation.oci-containers.containers.home-assistant or { };
      in {
        image = x.image or "";
        extraOptions = x.extraOptions or [ ];
        volumes = x.volumes or [ ];
        ports = x.ports or [ ];
      };
    unit.onFailure = c.systemd.services."podman-home-assistant".onFailure or [ ];
    backup = c.services.state-backups.services.home-assistant or { };
    dataDir = c.services.hass.dataDir or "";
    port = c.services.hass.port or 0;
    catalog = c.repo.web.catalog.home-assistant or null;
    edgeRoute = c.repo.web.hosts.oci-melb-1.services.home-assistant or null;
    edgeServes = builtins.hasAttr "home-assistant" (c.services.ingress.routes or { });
    failedAssertions = map (a: a.message) (builtins.filter (a: !a.assertion) (c.assertions or [ ]));
  };
in
{
  home-forge = host repo.nixosConfigurations.home-forge.config;
  oci-melb-1 = host repo.nixosConfigurations.oci-melb-1.config;
  la-admin-1 = host repo.nixosConfigurations.la-admin-1.config;
}
EOF

probe="$(nix eval --impure --no-write-lock-file --json -f "$tmp/probe.nix")" ||
  fail "the probe does not evaluate"

python3 - "$probe" <<'PYEOF' || fail "placement contract violated"
import json
import sys

data = json.loads(sys.argv[1])
errs = []

forge = data["home-forge"]
if not forge["hasContainer"]:
    errs.append("home-forge does not render the home-assistant container")

container = forge["container"]
image = container["image"]
if not image.startswith("ghcr.io/home-assistant/home-assistant:"):
    errs.append(f"image {image!r} is not Home Assistant's own")
if "@sha256:" not in image:
    errs.append(f"image {image!r} is not digest-pinned")
if "--network=host" not in container["extraOptions"]:
    errs.append(f"the container must share the host network namespace, got {container['extraOptions']!r}")
if container["ports"]:
    errs.append(f"a host-networked container must publish nothing, got {container['ports']!r}")
if f"{forge['dataDir']}:/config" not in container["volumes"]:
    errs.append(f"/config is not mounted from {forge['dataDir']}: {container['volumes']!r}")
if "/etc/localtime:/etc/localtime:ro" not in container["volumes"]:
    errs.append("the container does not mount the host clock")

# A crash-looping container is silent without a registration: `OnFailure=` only
# fires on the transition into `failed`, and nothing else reports it.
unit = forge["unit"]
if not any(h.endswith("notify-event@podman-home-assistant.service") for h in unit["onFailure"]):
    errs.append(f"the container does not notify on failure: {unit['onFailure']!r}")

# The recorder database is live: exported through the online backup API, and
# excluded from the raw copy of the configuration directory.
backup = forge["backup"]
if backup.get("mode") != "export":
    errs.append(f"the backup contract must be export-first, got {backup.get('mode')!r}")
database = f"{forge['dataDir']}/home-assistant_v2.db"
if database not in (backup.get("exclude") or []):
    errs.append(f"the live recorder database is not excluded from the raw copy: {backup.get('exclude')!r}")
for suffix in ("-wal", "-shm"):
    if database + suffix not in (backup.get("exclude") or []):
        errs.append(f"{database + suffix} is not excluded from the raw copy")
if not backup.get("exportPaths"):
    errs.append("the backup contract produces no export artifact")
if not any(".backup" in command and "sqlite3" in command for command in (backup.get("prepareCommands") or [])):
    errs.append(f"the recorder database is not exported with sqlite's backup API: {backup.get('prepareCommands')!r}")

# The catalog is what cross-host consumers dial, and the route is the published
# identity: the port must be the listener, the transport the provider's own.
catalog = forge["catalog"]
if catalog is None:
    errs.append("the home-assistant route is absent from the resolved catalog")
else:
    if catalog["endpoint"]["port"] != forge["port"]:
        errs.append(f"catalog endpoint port {catalog['endpoint']['port']} != listener {forge['port']}")
    if catalog["upstreamPort"] != forge["port"]:
        errs.append(f"catalog upstream port {catalog['upstreamPort']} != listener {forge['port']}")
    if catalog["exposureMode"] != "tailscale-upstream":
        errs.append(f"exposure mode {catalog['exposureMode']!r} must dial the provider directly")

route = forge["edgeRoute"]
if route is None:
    errs.append("the edge host has no resolved home-assistant route")
else:
    if route.get("publish") is not False:
        errs.append("the route must stay withheld until the instance is accepted")
    if route["subdomain"] != "hass":
        errs.append(f"subdomain {route['subdomain']!r}")
    if not route["access"]["requireCloudflareAccess"]:
        errs.append("once published, Access must sit outside Home Assistant's own login")
    if route["access"]["oidc"]["enabled"]:
        errs.append("this instance authenticates with Home Assistant's own login")
if forge["edgeServes"]:
    errs.append("the edge renders a site for a route that is not released")
if forge["failedAssertions"]:
    errs.append(f"home-forge violates an assertion: {forge['failedAssertions']}")

# Placement: the aspect is selected by the host that runs the workload only.
for other in ("oci-melb-1", "la-admin-1"):
    if data[other]["hasContainer"]:
        errs.append(f"{other} renders the home-assistant container without selecting the aspect")

if errs:
    print("\n".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF

echo "check-home-assistant-contract: PASS (home-forge host-networked container, export-first backup, withheld route)"
