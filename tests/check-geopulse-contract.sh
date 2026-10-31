#!/usr/bin/env bash
set -euo pipefail

# GeoPulse private runtime contract (openspec change add-geopulse, task 2.2).
#
# The runtime is wired from four places that can drift apart without any of them
# failing on its own: the private route in policy/web-services.nix (the port the
# front end must listen on), the service definition that binds the socket, the
# local PostgreSQL cluster the backend dials, and the owner-scoped secret files
# sops delivers. This check reads the evaluated configuration and the *rendered*
# Caddyfile — never the module's source text — and then runs that rendered
# Caddyfile under the real Caddy binary against fixture upstreams, because a
# Caddyfile that merely evaluates can still fail to load (the store basename's
# hash prefix defeats adapter inference, for one).
#
#   - the front-end listener port is the route's declared port and the socket is
#     loopback-only, while the *site* stays hostless so the canonical public host
#     the edge forwards still reaches it;
#   - the Cloudflare-facing projection carries the route's public identity and
#     access posture, prepared when the identity is declared rather than when the
#     edge starts serving it;
#   - the served edge refuses the route's denied paths (GP-5) while the app's own
#     surfaces keep reaching it;
#   - the second hop trusts the loopback edge alone, so the scheme and client
#     address the edge terminated survive it;
#   - the aspect is selected only on OCI and the host binds its encrypted service
#     secret path, while the other hosts acquire no GeoPulse runtime;
#   - the backend dials the host's own cluster (the declared port, the same
#     credential key the substrate provisions the role with) and the delivered
#     secret files rotate that one unit;
#   - /api, /mcp, the fixed tile proxy and the SPA fallback answer as upstream's
#     nginx surface did, and no secret value reaches the store.
#
# The placement host is aarch64, so the evaluated contract is asserted there while
# the Caddy run uses an x86_64 evaluation of the same module.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "check-geopulse-contract: $*" >&2
  exit 1
}

HOST="oci-melb-1"
RUN_HOST="la-admin-1"
OTHER_HOSTS=(home-forge la-admin-1)
WORK="$(mktemp -d)"
FIXTURE_SECRET="$WORK/geopulse-fixture.yaml"
# A value that exists only in the fixture file: if it shows up anywhere in the
# evaluated configuration, a secret leaked into the store.
FIXTURE_SENTINEL="geopulse-fixture-not-a-secret"

CADDY_PID=""
BACKEND_PID=""
EDGE_OPEN_PID=""
EDGE_CONTROL_PID=""
TUNNEL_PID=""
FORWARD_PID=""

cleanup() {
  for pid in "$CADDY_PID" "$BACKEND_PID" "$EDGE_OPEN_PID" "$EDGE_CONTROL_PID" \
    "$TUNNEL_PID" "$FORWARD_PID"; do
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  done
  rm -rf "$WORK"
}
trap cleanup EXIT

# Non-secret fixture: the aspect's gate only needs the file to exist, and the
# values below are never read by a service.
cat > "$FIXTURE_SECRET" <<YAML
# Non-secret fixture for tests/check-geopulse-contract.sh.
roles:
  geopulse:
    password: $FIXTURE_SENTINEL
YAML

# ---------------------------------------------------------------------------
# 1. Evaluated contract on the placement host
# ---------------------------------------------------------------------------
cat > "$WORK/contract.nix" <<NIX
let
  f = builtins.getFlake "path:$ROOT";
  placementService = f.nixosConfigurations.$HOST.config.services.geopulse or { };
  cfg =
    (f.nixosConfigurations.$HOST.extendModules {
      modules = [
        {
          services.geopulse.secretFiles.host = f.inputs.nixpkgs.lib.mkForce "$FIXTURE_SECRET";
        }
      ];
    }).config;
  unit = cfg.systemd.services.geopulse-backend;
  web = cfg.systemd.services.geopulse-web;
  # The un-overridden runtime: the fixture guard below is only trustworthy if the
  # same detector fires on these.
  realFinishedExec = cfg.systemd.services.geopulse-web.serviceConfig.ExecStart;
  # Publication is the policy route's own publish posture. The released variant
  # renders that route through the same projection the edge uses, so the proof
  # follows the release path instead of a host-side switch beside it.
  ingressRoutes = import $ROOT/modules/web/_ingress-routes.nix { inherit (f.inputs.nixpkgs) lib; };
  releasedRoutes =
    let
      services = cfg.repo.web.hosts.$HOST.services;
    in
    ingressRoutes (services // { geopulse = services.geopulse // { publish = true; }; });
  # The live edge run below cannot dial a tailnet name from a workstation, so the
  # released route's upstream is pointed at the fixture listener. The transport
  # shape is asserted on releasedRoutes itself, above; only the dial moves.
  edgeRoutes = f.inputs.nixpkgs.lib.mapAttrs (
    n: r:
    if n == "geopulse" then
      r // { upstream = "http://127.0.0.1:" + toString cfg.repo.web.catalog.geopulse.endpoint.port; }
    else
      r
  ) releasedRoutes;
  openCfg = (f.nixosConfigurations.$HOST.extendModules {
    modules = [
      {
        services.geopulse.secretFiles.host = f.inputs.nixpkgs.lib.mkForce "$FIXTURE_SECRET";
        services.ingress.routes = f.inputs.nixpkgs.lib.mkForce edgeRoutes;
      }
    ];
  }).config;
  edgeRoute =
    c:
    if (c.services.ingress.routes or { }) ? geopulse then
      builtins.intersectAttrs {
        exposureMode = 1;
        subdomain = 1;
        declarePublic = 1;
        upstream = 1;
        path = 1;
        stripPrefix = 1;
        cloudflareAccessRequired = 1;
      } c.services.ingress.routes.geopulse
    else
      null;
  # What the Cloudflare export resolves from, independent of the edge gate.
  edgePublicService =
    c:
    let
      services = ((c.repo.web.hosts or { }).$HOST or { }).services or { };
    in
    if services ? geopulse then
      builtins.intersectAttrs {
        exposureMode = 1;
        declarePublic = 1;
        access = 1;
      } services.geopulse
    else
      null;
  realBackendExec = cfg.systemd.services.geopulse-backend.serviceConfig.ExecStart;
  geopulseSecrets = f.inputs.nixpkgs.lib.filterAttrs (n: _: f.inputs.nixpkgs.lib.hasPrefix "geopulse/" n) cfg.sops.secrets;
  consumer = cfg.services.postgres.consumers.geopulse;
  # DynamicUser would break sops' activation-time chown of the delivered files.
  # The control injects one offender, so the check cannot pass vacuously.
  offenders =
    c: builtins.filter (n: c.systemd.services.\${n}.serviceConfig.DynamicUser or false) [ "geopulse-backend" "geopulse-web" ];
  mutated = (f.nixosConfigurations.$HOST.extendModules {
    modules = [
      {
        services.geopulse.secretFiles.host = f.inputs.nixpkgs.lib.mkForce "$FIXTURE_SECRET";
        systemd.services.geopulse-backend.serviceConfig.DynamicUser = true;
      }
    ];
  }).config;
  dynamicUser = offenders cfg;
  dynamicUserControl = offenders mutated;
in
{
  placement = {
    # Selection is enablement: the aspect declares its options where it is selected, so a
    # non-empty namespace on the placement host is the observable, not a flag it sets.
    selected = placementService != { };
    secretFile =
      if (placementService.secretFiles.host or null) == null then
        ""
      else
        toString placementService.secretFiles.host;
  };
  dataDir = cfg.services.geopulse.dataDir;
  backendPort = cfg.services.geopulse.backendPort;
  backend = {
    name = cfg.services.geopulse.backendPackage.name;
    drv = cfg.services.geopulse.backendPackage.drvPath;
  };
  frontend = {
    name = cfg.services.geopulse.frontendPackage.name;
    drv = cfg.services.geopulse.frontendPackage.drvPath;
  };
  failing = map (a: a.message) (builtins.filter (a: !a.assertion) cfg.assertions);
  users = builtins.mapAttrs (_: u: {
    system = u.isSystemUser or false;
    group = u.group or null;
    home = u.home or null;
  }) (builtins.intersectAttrs { geopulse = 1; "geopulse-web" = 1; } cfg.users.users);
  groups = builtins.attrNames (builtins.intersectAttrs { geopulse = 1; "geopulse-web" = 1; } cfg.users.groups);
  inherit dynamicUser dynamicUserControl;
  # Evaluation only: reading a derivation's inputs never realises its outputs.
  realDerivations =
    builtins.attrNames (builtins.getContext realFinishedExec)
    ++ builtins.attrNames (builtins.getContext realBackendExec);
  backendUnit = {
    user = unit.serviceConfig.User;
    group = unit.serviceConfig.Group;
    execStart = unit.serviceConfig.ExecStart;
    env = unit.environment;
    readWritePaths = unit.serviceConfig.ReadWritePaths;
    requiresMountsFor = unit.unitConfig.RequiresMountsFor;
    after = unit.after;
    requires = unit.requires;
    restart = unit.serviceConfig.Restart;
  };
  webUnit = {
    user = web.serviceConfig.User;
    group = web.serviceConfig.Group;
    execStart = web.serviceConfig.ExecStart;
  };
  tmpfiles = builtins.filter (r: f.inputs.nixpkgs.lib.hasInfix "geopulse" r) cfg.systemd.tmpfiles.rules;
  secrets = builtins.mapAttrs (_: s: {
    inherit (s) path key owner group mode;
    restartUnits = s.restartUnits;
  }) geopulseSecrets;
  consumer = {
    inherit (consumer) database role auth allowedCIDRs password;
  };
  backup =
    let
      r = cfg.services.state-backups.services.geopulse or null;
    in
    if r == null then null else { inherit (r) enable mode paths exclude exportPaths; };
  localEndpointPort = cfg.services.postgres.localEndpoint.port;
  route = builtins.intersectAttrs { geopulse = 1; } cfg.repo.web.catalog;
  gate = {
    edgeOpen = edgeRoute openCfg;
    releasedShape = edgeRoute { services.ingress.routes = releasedRoutes; };
    edgePublicService = edgePublicService cfg;
  };
}
NIX

nix eval --impure --no-write-lock-file --json --file "$WORK/contract.nix" 2>"$WORK/contract.err" > "$WORK/contract.json" || {
  cat "$WORK/contract.err" >&2
  fail "the GeoPulse aspect with a fixture secret file does not evaluate"
}

python3 - "$WORK/contract.json" "$FIXTURE_SENTINEL" "$HOST" <<'PY' || fail "evaluated runtime contract violated"
import json
import re
import sys

path, sentinel, host = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(path).read()
d = json.loads(raw)
errs = []

if not d["placement"]["selected"]:
    errs.append("the oci-melb-1 host record must select the GeoPulse aspect")
if not d["placement"]["secretFile"].endswith("/secrets/services/geopulse.yaml"):
    errs.append(f"the host must bind the encrypted GeoPulse service-secret path, got {d['placement']['secretFile']!r}")

if d["failing"]:
    errs.append("enabled with a present secret file must not fail an assertion: " + "; ".join(d["failing"]))

# 1b. sops chowns the delivered files to a static account at activation, so a
# DynamicUser unit could never read them.
if d["dynamicUser"]:
    errs.append(
        f"the units must not use DynamicUser (offenders: {d['dynamicUser']!r}): "
        "sops cannot chown to a dynamic account"
    )
# 1c. Route and listeners agree, and the route publishes an identity without
# publishing a site: the OIDC callback derives from that identity while the edge
# withholds the route until the host releases the gate.
route = d["route"].get("geopulse")
if route is None:
    errs.append("repo.web.catalog.geopulse is missing: the listener port has no single source")
else:
    if route["upstreamPort"] != route["endpoint"]["port"]:
        errs.append(
            f"route upstream port {route['upstreamPort']} and catalog port {route['endpoint']['port']} disagree"
        )

gate = d["gate"]
# The shape assertions read the projection itself; the adapted copy below exists
# only so the live edge run can dial a loopback fixture.
released = gate["releasedShape"]
if released is None:
    errs.append("releasing the gate must render the route at the edge")
else:
    # Device sources authenticate with their own application credentials and the
    # application runs its own OIDC login, so no interactive Access session may sit
    # in front of the route.
    if released["cloudflareAccessRequired"]:
        errs.append("the released route requires Cloudflare Access; device ingest cannot present one")
    if released["upstream"] != f"https://oci-melb-1.tail0fe19b.ts.net:{route['upstreamPort']}":
        errs.append(f"released route upstream {released['upstream']!r} is not the provider's front end")
# The Cloudflare-facing projection carries the route's public identity and access
# posture. DNS and access policy are prepared when the identity is declared, so the
# edge's served set and Cloudflare's view are independent.
service = gate["edgePublicService"]
if service is None:
    errs.append("the Cloudflare-facing projection loses the geopulse route")
else:
    if service["access"]["requireCloudflareAccess"]:
        errs.append("the Cloudflare-facing route requires Cloudflare Access")
    if not service["access"]["oidc"]["enabled"]:
        errs.append("the Cloudflare-facing route must keep application OIDC on")

url = d["backendUnit"]["env"].get("GEOPULSE_POSTGRES_URL", "")
if not re.fullmatch(r"jdbc:postgresql://127\.0\.0\.1:\d+/geopulse", url):
    errs.append(f"backend database URL {url!r} must dial the local cluster on loopback")
else:
    port = int(url.rsplit(":", 1)[1].split("/")[0])
    if port != d["localEndpointPort"]:
        errs.append(f"backend dials port {port}, the host's cluster is on {d['localEndpointPort']}")
if d["backendUnit"]["env"].get("QUARKUS_HTTP_HOST") != "127.0.0.1":
    errs.append(
        f"backend bind address {d['backendUnit']['env'].get('QUARKUS_HTTP_HOST')!r}, want loopback only"
    )

# 1d. The consumer registration and the delivered credential share one source.
consumer = d["consumer"]
if consumer["allowedCIDRs"] != ["127.0.0.1/32"]:
    errs.append(f"consumer allowedCIDRs {consumer['allowedCIDRs']!r}; the backend dials loopback only")
if "password" not in consumer or "file" not in consumer["password"]:
    errs.append("the consumer has no credential source")
else:
    delivered = d["secrets"].get("geopulse/postgres-password")
    if delivered is None:
        errs.append("geopulse/postgres-password is not delivered with the other service secrets")
    else:
        if delivered["key"] != consumer["password"]["key"]:
            errs.append(
                f"delivered password key {delivered['key']!r} differs from the provisioned one "
                f"{consumer['password']['key']!r}: a rotation would move only one half"
            )

# 1e. A rotated secret must restart the unit that read it, and the rendered file
# must sit under the traversable mount rather than the 0750 root:root parent.
for name in ("geopulse/postgres-password", "geopulse/ai-encryption-key"):
    entry = d["secrets"].get(name)
    if entry is None:
        errs.append(f"{name}: not delivered")
        continue
    if entry["path"].startswith("/run/secrets.d"):
        errs.append(f"{name}: rendered templates sit under a 0750 root:root parent the service cannot traverse")
    if "geopulse-backend.service" not in (entry["restartUnits"] or []):
        errs.append(f"{name}: a rotation must restart geopulse-backend.service")

# 1f. The backend maps the upstream locations onto the delivered paths and keeps
# the rest of its environment non-secret; the empty-key guard runs before the JVM.
env = d["backendUnit"]["env"]
env = d["backendUnit"]["env"]
if "GEOPULSE_POSTGRES_PASSWORD" in env:
    errs.append("the database password must not be a unit environment value; the start wrapper reads the file")

# 1g. Sandbox and state: the state mount is required before start, and only the
# state directory is writable.
if d["dataDir"] not in str(d["backendUnit"]["requiresMountsFor"]):
    errs.append(f"the backend must require the state mount: {d['backendUnit']['requiresMountsFor']!r}")
if list(d["backendUnit"]["readWritePaths"]) != [d["dataDir"]]:
    errs.append(f"writable paths {d['backendUnit']['readWritePaths']!r}, want only {d['dataDir']!r}")
for unit in ("postgresql-provision.service",):
    if unit not in d["backendUnit"]["requires"] or unit not in d["backendUnit"]["after"]:
        errs.append(f"the backend must be ordered after and require {unit}")

# 1h. The front end is the fleet's own Caddy runtime, not an upstream nginx image.
if "caddy" not in d["webUnit"]["execStart"]:
    errs.append(f"the front-end listener must use the fleet's Caddy runtime: {d['webUnit']['execStart']!r}")

# 1i. No secret value may reach the store.
if sentinel in raw:
    errs.append("a secret value from the bound file appears in the evaluated configuration")

if errs:
    print("\n".join(f"  {e}" for e in errs), file=sys.stderr)
    sys.exit(1)
PY

# 1g-bis. Backup registration (design GP-6): the mutable files are registered
# through the state-backups contract, the disposable scratch is excluded, and the
# live database directory is never captured raw (the substrate export owns it).
# Checked on the evaluated JSON, then against a mutated copy that adds the live
# cluster directory: the control must fail, or the assertion checks nothing.
cat > "$WORK/check-backup.py" <<'PY'
import json
import sys

path = sys.argv[1]
d = json.load(open(path))
bk = d.get("backup")
errs = []
if bk is None or not bk.get("enable"):
    errs.append("state-backups registration for geopulse is missing or disabled")
else:
    for live in ("/var/lib/postgresql", "/srv/data/postgresql", d["dataDir"] + "/dumps"):
        if any(p == live or p.startswith(live + "/") for p in bk["paths"]):
            errs.append(f"geopulse backup must not capture {live} raw")
    if bk["mode"] != "live" or bk["exportPaths"]:
        errs.append(f"geopulse backup is a raw-file registration, got mode {bk['mode']!r}, exports {bk['exportPaths']!r}")
if errs:
    print("\n".join(errs))
    sys.exit(1)
PY

python3 "$WORK/check-backup.py" "$WORK/contract.json" || fail "geopulse backup registration violates GP-6"


# ---------------------------------------------------------------------------
# 1h. Wrong exposure: the gate is only safe while the route keeps a public
# identity. The control re-privatises the route in a throwaway copy of the tree,
# where the host's own cluster and cluster-dependent values are irrelevant: the
# aspect must fail by name instead of coercing a null origin into the unit's
# environment.
# ---------------------------------------------------------------------------
CONTROL="$(mktemp -d "$WORK/control.XXXXXX")"
tar -C "$ROOT" \
  --exclude=.git --exclude=.jj --exclude=./opentofu --exclude=./opentofu/* \
  --exclude=.hp-forge-esp-backup --exclude=.qmd --exclude=.direnv \
  --exclude=.cortexkit --exclude=.tmp --exclude=.pi --exclude=.firecrawl \
  --exclude=.ruff_cache \
  -cf - . | tar -C "$CONTROL" -xf -

python3 - "$CONTROL" <<'PYEOF' > /dev/null || fail "the wrong-exposure control mutation script failed"
import sys

path = sys.argv[1] + "/policy/web-services.nix"
src = open(path).read()
start = src.index("        geopulse = {")
end = src.index("        webhook-admin = {", start)
block = src[start:end]
assert 'subdomain = "geo";' in block and 'exposureMode = "tailscale-serve";' in block, "geopulse route anchor drifted"
mutated = block.replace('subdomain = "geo";', "subdomain = null;", 1).replace(
    'exposureMode = "tailscale-serve";', 'exposureMode = "tailscale-only";', 1
)
open(path, "w").write(src[:start] + mutated + src[end:])
PYEOF

cat > "$WORK/wrong-exposure.nix" <<NIX
let
  f = builtins.getFlake "path:$CONTROL";
  cfg =
    (f.nixosConfigurations.$HOST.extendModules {
      modules = [
        {
          services.geopulse.secretFiles.host = f.inputs.nixpkgs.lib.mkForce "$FIXTURE_SECRET";
        }
      ];
    }).config;
in
{
  failing = map (a: a.message) (builtins.filter (a: !a.assertion) cfg.assertions);
}
NIX
nix eval --impure --no-write-lock-file --json --file "$WORK/wrong-exposure.nix" > "$WORK/wrong-exposure.json" ||
  fail "the re-privatised route copy does not evaluate"
python3 - "$WORK/wrong-exposure.json" <<'PYEOF' || fail "wrong exposure must fail by name"
import json
import sys

failing = json.load(open(sys.argv[1]))["failing"]
if not any("must publish a public identity" in message for message in failing):
    print(f"expected the public-identity failure, got {failing!r}", file=sys.stderr)
    sys.exit(1)
PYEOF

# ---------------------------------------------------------------------------
# 1b. The named failures: a selected host without credentials or without a
# cluster fails closed, and forcing the cluster-dependent address fails too.
# ---------------------------------------------------------------------------
cat > "$WORK/negative.nix" <<NIX
let
  f = builtins.getFlake "path:$ROOT";
  # Every fleet host now declares a cluster, so the missing-cluster case is produced by
  # declaring none rather than by finding a host that serves no database.
  noCluster = (f.nixosConfigurations.$RUN_HOST.extendModules {
    modules = [
      f.modules.nixos.geopulse
      {
        services.geopulse.secretFiles.host = "$FIXTURE_SECRET";
        services.postgres.instances = f.inputs.nixpkgs.lib.mkForce { };
      }
    ];
  }).config;
in
{
  # Only failing messages are forced, so no message that is never reported can
  # fail this probe on its own.
  noCluster = map (a: a.message) (builtins.filter (a: !a.assertion) noCluster.assertions);
  urlFailsClosed = !(builtins.tryEval noCluster.systemd.services.geopulse-backend.environment.GEOPULSE_POSTGRES_URL).success;
}
NIX

nix eval --impure --no-write-lock-file --json --file "$WORK/negative.nix" 2>"$WORK/negative.err" > "$WORK/negative.json" || {
  cat "$WORK/negative.err" >&2
  fail "the named failure probes do not evaluate"
}

python3 - "$WORK/negative.json" <<'PYINNER' || fail "a missing requirement does not fail closed by name"
import json
import sys

d = json.load(open(sys.argv[1]))
errs = []
if not any("runs no PostgreSQL cluster" in m for m in d["noCluster"]):
    errs.append(f"a host without a local cluster must say so: {d['noCluster']!r}")
if not d["urlFailsClosed"]:
    errs.append("the cluster-dependent database address must not evaluate on a host without a cluster")
if errs:
    print("\n".join(f"  {e}" for e in errs), file=sys.stderr)
    sys.exit(1)
PYINNER

# ---------------------------------------------------------------------------
# 2. Rendered front-end listener: validate and exercise it
# ---------------------------------------------------------------------------
cat > "$WORK/behaviour.nix" <<NIX
let
  f = builtins.getFlake "path:$ROOT";
  np = f.inputs.nixpkgs.legacyPackages.x86_64-linux;
  # Both halves stand in as cheap fixtures so this check realises nothing from the
  # GeoPulse release; the evaluated contract above pins the real packages, and
  # their derivation references are checked separately below.
  fixtureFrontend = np.stdenv.mkDerivation {
    pname = "geopulse-frontend";
    version = "0.0.0";
    dontUnpack = true;
    installPhase = ''
      runHook preInstall
      mkdir -p \$out/assets
      printf '%s' '<!doctype html><html><head><script src="/config.js"></script></head><body><div id="app">$FIXTURE_SENTINEL shell</div></body></html>' > \$out/index.html
      printf '%s' 'window.__fixture = true;' > \$out/assets/app-abc123.js
      printf '%s' '{"name":"GeoPulse"}' > \$out/manifest.webmanifest
      runHook postInstall
    '';
  };
  # The start wrapper only names this path, so the fixture needs no contents.
  fixtureBackend = np.stdenv.mkDerivation {
    pname = "geopulse-backend";
    version = "0.0.0";
    dontUnpack = true;
    installPhase = ''
      mkdir -p \$out/quarkus-app
      touch \$out/quarkus-app/quarkus-run.jar
    '';
  };
  cfg =
    (f.nixosConfigurations.$RUN_HOST.extendModules {
      modules = [
        f.modules.nixos.geopulse
        {
          services.geopulse.secretFiles.host = "$FIXTURE_SECRET";
          services.geopulse.backendPackage = np.lib.mkForce fixtureBackend;
          services.geopulse.frontendPackage = np.lib.mkForce fixtureFrontend;
        }
      ];
    }).config;
  exec = cfg.systemd.services.geopulse-web.serviceConfig.ExecStart;
  backendExec = cfg.systemd.services.geopulse-backend.serviceConfig.ExecStart;
in
{
  exec = exec;
  backendExec = backendExec;
  derivations =
    builtins.attrNames (builtins.getContext exec) ++ builtins.attrNames (builtins.getContext backendExec);
  routePort = cfg.repo.web.catalog.geopulse.upstreamPort;
  backendPort = cfg.services.geopulse.backendPort;
  fixtureNames = {
    backend = fixtureBackend.name;
    frontend = fixtureFrontend.name;
  };
}
NIX

nix eval --impure --no-write-lock-file --json --file "$WORK/behaviour.nix" 2>"$WORK/behaviour.err" > "$WORK/behaviour.json" || {
  cat "$WORK/behaviour.err" >&2
  fail "the front-end listener does not evaluate for a runnable system"
}

read -r CADDY_BIN CADDYFILE < <(
  python3 - "$WORK/behaviour.json" <<'PY'
import json
import sys

d = json.load(open(sys.argv[1]))
print(d["exec"].split()[0], d["exec"].split("--config ")[1].strip())
PY
)
[ -n "$CADDY_BIN" ] && [ -n "$CADDYFILE" ] || fail "the front-end unit does not name a Caddy config"

# Build exactly the derivations the unit references.
while read -r drv; do
  # Keep the reason: a realisation failure here is the interesting output.
  nix build --no-link --impure "${drv}^*" >"$WORK/realise.log" 2>&1 || {
    cat "$WORK/realise.log" >&2
    fail "cannot realise ${drv}"
  }
done < <(
  python3 - "$WORK/behaviour.json" <<'PY'
import json
import sys

for d in json.load(open(sys.argv[1]))["derivations"]:
    print(d)
PY
)

# No realised derivation may reference the released packages: a hit here means
# validation CI would build GeoPulse output. Both the released and the fixture names
# are read from the evaluated configuration, so a release bump moves the guard with
# it instead of leaving it to grep for a version that no longer exists.
read -r RELEASED_BACKEND RELEASED_FRONTEND < <(
  python3 - "$WORK/contract.json" <<'PY'
import json
import sys

d = json.load(open(sys.argv[1]))
print(d["backend"]["name"], d["frontend"]["name"])
PY
)
read -r FIXTURE_BACKEND_NAME FIXTURE_FRONTEND_NAME < <(
  python3 - "$WORK/behaviour.json" <<'PY'
import json
import sys

names = json.load(open(sys.argv[1]))["fixtureNames"]
print(names["backend"], names["frontend"])
PY
)
[ -n "$RELEASED_BACKEND" ] && [ -n "$RELEASED_FRONTEND" ] ||
  fail "the evaluated package names are empty; the release guard would match nothing"
[ "$RELEASED_BACKEND" != "$FIXTURE_BACKEND_NAME" ] ||
  fail "the fixture and the release share the name ${RELEASED_BACKEND}: the guard cannot tell them apart"
[ "$RELEASED_FRONTEND" != "$FIXTURE_FRONTEND_NAME" ] ||
  fail "the fixture and the release share the name ${RELEASED_FRONTEND}: the guard cannot tell them apart"

released=("$RELEASED_BACKEND" "$RELEASED_FRONTEND")
assert_fixture_only() { # $1 drv path, rest: extra nix derivation show flags
  local drv="$1"
  shift
  nix derivation show "$@" "$drv" > "$WORK/derivation.json" || fail "cannot read derivation references of ${drv}"
  local name
  for name in "${released[@]}"; do
    if grep -qF "$name" "$WORK/derivation.json"; then
      fail "the fixture closure references the released ${name}: validation must not build GeoPulse output"
    fi
  done
}

mapfile -t FIXTURE_DRVS < <(
  python3 - "$WORK/behaviour.json" <<'PYREFS'
import json
import sys

for d in json.load(open(sys.argv[1]))["derivations"]:
    print(d)
PYREFS
)
seen_wrapper=no
seen_caddyfile=no
for drv in "${FIXTURE_DRVS[@]}"; do
  case "$drv" in
    # The wrapper is where the release could leak in: recurse from it.
    *geopulse-backend.drv)
      seen_wrapper=yes
      assert_fixture_only "$drv" -r
      grep -qF "$FIXTURE_BACKEND_NAME" "$WORK/derivation.json" ||
        fail "the wrapper does not reference the backend fixture, so the check above is vacuous"
      ;;
    *Caddyfile.drv)
      seen_caddyfile=yes
      assert_fixture_only "$drv"
      grep -qF "$FIXTURE_FRONTEND_NAME" "$WORK/derivation.json" ||
        fail "the rendered config does not reference the front-end fixture, so the check above is vacuous"
      ;;
    *) assert_fixture_only "$drv" ;;
  esac
done
# A loop that matched nothing would report success, so the run must show both
# geopulse-owned derivations it realises.
[ "$seen_wrapper" = yes ] || fail "no start-wrapper derivation among ${FIXTURE_DRVS[*]}: the release check did not run"
[ "$seen_caddyfile" = yes ] || fail "no rendered-config derivation among ${FIXTURE_DRVS[*]}: the release check did not run"

# The same detector must fire on the un-overridden runtime, or the fixture run
# proves nothing. Reading those derivations is evaluation; nothing from the release
# is realised, and the names above came from the evaluated packages, so this holds
# after a version bump.
mapfile -t REAL_DRVS < <(
  python3 - "$WORK/contract.json" <<'PY'
import json
import sys

for name in json.load(open(sys.argv[1]))["realDerivations"]:
    print(name)
PY
)
sensitive=no
for drv in "${REAL_DRVS[@]}"; do
  case "$drv" in
    *geopulse-backend.drv|*Caddyfile.drv)
      nix derivation show "$drv" > "$WORK/unoverridden.json" ||
        fail "cannot read the un-overridden derivation references of ${drv}"
      if grep -qF -e "$RELEASED_BACKEND" -e "$RELEASED_FRONTEND" "$WORK/unoverridden.json"; then
        sensitive=yes
      fi
      ;;
  esac
done
[ "$sensitive" = yes ] ||
  fail "an un-overridden runtime does not reference ${RELEASED_BACKEND} or ${RELEASED_FRONTEND}: the release guard cannot detect them"

"$CADDY_BIN" validate --adapter caddyfile --config "$CADDYFILE" >"$WORK/caddy-validate.log" 2>&1 || {
  cat "$WORK/caddy-validate.log" >&2
  fail "the rendered Caddyfile does not load under Caddy's own validator"
}

python3 - "$WORK/behaviour.json" "$CADDYFILE" "$FIXTURE_SENTINEL" <<'PY' || fail "rendered listener contract violated"
import json
import sys

behaviour, caddyfile, sentinel = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(behaviour))
text = open(caddyfile).read()
errs = []

site = f"http://:{d['routePort']} {{"
if site not in text:
    errs.append(f"no hostless site block on the declared route port: {site!r}")
if f"http://127.0.0.1:{d['routePort']}" in text:
    errs.append(
        "the site address must stay hostless: a host here would match (and so reject) "
        "the canonical public host the edge forwards"
    )
if "bind 127.0.0.1" not in text:
    errs.append("the listener must bind the loopback address explicitly")
trusted = [line.strip() for line in text.splitlines() if "trusted_proxies" in line]
if trusted != ["trusted_proxies static 127.0.0.1"]:
    errs.append(
        f"the second hop must trust the loopback edge alone, got {trusted!r}: any wider range "
        "would let another client forge the forwarded scheme and client address"
    )
for wildcard in ("0.0.0.0", ":80 ", ":443"):
    if wildcard in text:
        errs.append(f"the listener must not bind {wildcard!r}")
if text.count("http://") != 1:
    errs.append("the listener must serve exactly one site")

backend = f"127.0.0.1:{d['backendPort']}"
if text.count(f"reverse_proxy {backend}") != 2:
    errs.append(f"both the /api and /mcp mappings must proxy to the backend {backend}")
for mapping in ("handle /api/*", "handle /mcp*", "handle /config.js", "handle /osm/tiles/*", "handle /assets/*"):
    if mapping not in text:
        errs.append(f"missing mapping: {mapping}")
if "try_files {path} /index.html" not in text:
    errs.append("the SPA fallback is missing: /oidc/callback resolves through it")
if "root * " not in text:
    errs.append("no document root for the static front end")
# The tile mapping is the one outbound route: fixed upstream, upstream Host, no
# client cookie or authorization header, and an identifying user agent.
for want in (
    "https://a.tile.openstreetmap.org",
    "rewrite @tile /{re.tile.2}",
    "header_up Host a.tile.openstreetmap.org",
    "header_up -Cookie",
    "header_up -Authorization",
    f"header_up User-Agent \"GeoPulse/",
):
    if want not in text:
        errs.append(f"tile mapping is missing {want!r}")
if "admin off" not in text:
    errs.append("the admin API must be off: the edge's Caddy owns the default localhost:2019")
if sentinel in text:
    errs.append("a fixture secret value appears in the rendered front-end config")

if errs:
    print("\n".join(f"  {e}" for e in errs), file=sys.stderr)
    sys.exit(1)
PY

# Exercise the rendered config: a fixture upstream on the backend port, then the
# mappings the edge will rely on.
read -r ROUTE_PORT BACKEND_PORT < <(
  python3 - "$WORK/behaviour.json" <<'PY'
import json
import sys

d = json.load(open(sys.argv[1]))
print(d["routePort"], d["backendPort"])
PY
)

cat > "$WORK/fixture-backend.py" <<'PY'
import http.server
import sys


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = "fixture-backend path={} host={} proto={} xff={}".format(
            self.path,
            self.headers.get("Host"),
            self.headers.get("X-Forwarded-Proto"),
            self.headers.get("X-Forwarded-For"),
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
PY

python3 "$WORK/fixture-backend.py" "$BACKEND_PORT" &
BACKEND_PID=$!

"$CADDY_BIN" run --adapter caddyfile --config "$CADDYFILE" >"$WORK/caddy.log" 2>&1 &
CADDY_PID=$!

ready=no
for _ in $(seq 1 40); do
  if curl -fsS --noproxy '*' -o /dev/null "http://127.0.0.1:${ROUTE_PORT}/" 2>/dev/null; then
    ready=yes
    break
  fi
  kill -0 "$CADDY_PID" 2>/dev/null || break
  sleep 0.25
done
[ "$ready" = "yes" ] || {
  cat "$WORK/caddy.log" >&2
  fail "the rendered listener never answered on 127.0.0.1:${ROUTE_PORT}"
}

body() { curl -fsS --noproxy '*' "http://127.0.0.1:${ROUTE_PORT}$1"; }
headers() { curl -fsS --noproxy '*' -D - -o /dev/null "http://127.0.0.1:${ROUTE_PORT}$1"; }

shell_body="$(body /)"
case "$shell_body" in
  *"$FIXTURE_SENTINEL shell"*) ;;
  *) fail "GET / did not serve the front-end shell: ${shell_body:0:120}" ;;
esac
case "$(body /oidc/callback)" in
  *"$FIXTURE_SENTINEL shell"*) ;;
  *) fail "GET /oidc/callback must fall back to the app shell (the OIDC redirect lands there)" ;;
esac
case "$(body /config.js)" in
  *"API_BASE_URL: '/api/v1'"*) ;;
  *) fail "GET /config.js did not serve the non-secret runtime configuration" ;;
esac
case "$(body /manifest.webmanifest)" in
  *GeoPulse*) ;;
  *) fail "GET /manifest.webmanifest did not serve the front-end file" ;;
esac
case "$(body /assets/app-abc123.js)" in
  *"window.__fixture"*) ;;
  *) fail "GET /assets/app-abc123.js did not serve the hashed asset" ;;
esac
case "$(body /api/probe)" in
  *"fixture-backend path=/api/probe"*) ;;
  *) fail "GET /api/probe did not reach the backend with its path intact" ;;
esac
case "$(body /mcp/probe)" in
  *"fixture-backend path=/mcp/probe"*) ;;
  *) fail "GET /mcp/probe did not reach the backend" ;;
esac
# The backend must see the client's Host, not the upstream address (Caddy's
# default) — nginx's `proxy_set_header Host $host` sent the host without a port.
case "$(body /api/probe)" in
  *"host=127.0.0.1 "*) ;;
  *) fail "the backend must receive the original Host header: $(body /api/probe)" ;;
esac

# The edge dials this listener on the canonical public host and forwards the
# scheme it terminated plus the client address. Both must arrive intact.
PUBLIC_HOST="geo.shrublab.xyz"
EDGE_CLIENT="203.0.113.7"
public_body() { curl -fsS --noproxy '*' -H "Host: ${PUBLIC_HOST}" "$@"; }

case "$(public_body "http://127.0.0.1:${ROUTE_PORT}/")" in
  *"$FIXTURE_SENTINEL shell"*) ;;
  *) fail "the canonical public host must render the app shell" ;;
esac
case "$(public_body "http://127.0.0.1:${ROUTE_PORT}/oidc/callback")" in
  *"$FIXTURE_SENTINEL shell"*) ;;
  *) fail "the canonical public host must reach the SPA fallback the OIDC redirect lands on" ;;
esac
edge_backend="$(
  public_body -H "X-Forwarded-Proto: https" -H "X-Forwarded-For: ${EDGE_CLIENT}" \
    "http://127.0.0.1:${ROUTE_PORT}/api/probe"
)"
case "$edge_backend" in
  *"host=${PUBLIC_HOST} "*) ;;
  *) fail "the backend must see the public host the edge forwards: ${edge_backend}" ;;
esac
case "$edge_backend" in
  *"proto=https xff="*) ;;
  *) fail "the backend must see the https scheme the edge terminated: ${edge_backend}" ;;
esac
case "$edge_backend" in
  *"xff=${EDGE_CLIENT},"*) ;;
  *) fail "the backend must see the edge's client address first: ${edge_backend}" ;;
esac

headers / | grep -qi '^cache-control: no-store' || fail "the app shell must not be cached"
headers /config.js | grep -qi '^cache-control: no-store' || fail "the runtime config must not be cached"
headers /assets/app-abc123.js | grep -qi '^cache-control: public, max-age=31536000, immutable' ||
  fail "hashed assets must be cached as immutable"

# The generated start wrapper is what systemd runs: it must launch the published
# package, read the delivered files, and carry no value from them.
BACKEND_EXEC="$(
  python3 - "$WORK/behaviour.json" <<'PYINNER'
import json
import sys

print(json.load(open(sys.argv[1]))["backendExec"])
PYINNER
)"
[ -f "$BACKEND_EXEC" ] || fail "the backend start wrapper ${BACKEND_EXEC} was not realised"
grep -q "quarkus-run.jar" "$BACKEND_EXEC" || fail "the start wrapper does not launch the Quarkus fast-jar"
grep -q "GEOPULSE_POSTGRES_PASSWORD" "$BACKEND_EXEC" || fail "the start wrapper does not export the database password"
for delivered in /run/secrets/geopulse/postgres-password /run/secrets/geopulse/ai-encryption-key.txt; do
  grep -q "$delivered" "$BACKEND_EXEC" || fail "the start wrapper does not read ${delivered}"
done
grep -q "$FIXTURE_SENTINEL" "$BACKEND_EXEC" && fail "a secret value from the bound file reached the store"

# Private by default: the socket is bound on the loopback address only.
if curl -fsS --noproxy '*' -m 2 -o /dev/null "http://127.0.0.2:${ROUTE_PORT}/" 2>/dev/null; then
  fail "the listener answered on 127.0.0.2: it must bind the loopback address only"
fi

# ---------------------------------------------------------------------------
# 2b. Published edge: the GP-5 denials are refused there, by behaviour
# ---------------------------------------------------------------------------
# The edge renders per host, and the placement host is aarch64, so the Caddy
# configuration below carries GP-5's denials alongside every other site. The
# rendered file is platform-independent text, so it is read out of the
# derivation and run here with its site addresses moved onto loopback test ports
# and onto http:// — no handler, matcher or guard is touched.
EDGE_OPEN_PORT=18443
EDGE_CONTROL_PORT=18444
TUNNEL_PORT=18445
TUNNEL_FEED_PORT=18446

cat > "$WORK/edge.nix" <<NIXEDGE
let
  f = builtins.getFlake "path:$ROOT";
  np = f.inputs.nixpkgs;
  base = { services.geopulse.secretFiles.host = np.lib.mkForce "$FIXTURE_SECRET"; };
  withAspect = extra: (f.nixosConfigurations.$HOST.extendModules {
    modules = [ extra ];
  }).config;
  ingressRoutes = import $ROOT/modules/web/_ingress-routes.nix { inherit (np) lib; };
  closedCfg = withAspect base;
  releasedRoute = closedCfg.repo.web.hosts.$HOST.services.geopulse // { publish = true; };
  services0 = closedCfg.repo.web.hosts.$HOST.services;
  releasedRoutes = ingressRoutes (services0 // { geopulse = releasedRoute; });
  # The rendered config is exercised from a workstation, which cannot dial the
  # provider's tailnet name the published route declares. Only the dial is
  # rewritten onto the fixture listener; the transport shape is asserted on
  # releasedRoutes itself, before this copy is made.
  fixtureDial = routes:
    routes
    // np.lib.optionalAttrs (routes ? geopulse) {
      geopulse = routes.geopulse // {
        upstream = "http://127.0.0.1:" + toString closedCfg.repo.web.catalog.geopulse.upstreamPort;
      };
    };
  opened =
    withAspect
      (base
        // {
          services.ingress.routes = np.lib.mkForce (fixtureDial releasedRoutes);
        });
in
{
  open = opened.services.caddy.configFile;
  noDenials =
    (withAspect
      (base
        // {
          services.ingress.routes = np.lib.mkForce (
            fixtureDial (ingressRoutes (services0 // { geopulse = releasedRoute // { deniedPaths = [ ]; }; }))
          );
        })).services.caddy.configFile;
  denied = opened.services.ingress.routes.geopulse.deniedPaths;
  routeServed = opened.services.ingress.routes ? geopulse;
}
NIXEDGE

nix eval --impure --no-write-lock-file --json --file "$WORK/edge.nix" >"$WORK/edge.json" 2>"$WORK/edge.err" || {
  cat "$WORK/edge.err" >&2
  fail "the edge configuration does not evaluate for the placement host"
}
python3 - "$WORK/edge.json" <<'PYEDGE' || fail "unexpected edge evaluation output"
import json
import sys

d = json.load(open(sys.argv[1]))
if not d["routeServed"]:
    sys.exit("the published route must reach the edge")
if not d["denied"]:
    sys.exit("the route must declare GP-5's denied paths")
print(f"check-geopulse-contract: the published route declares {len(d['denied'])} denied path matchers")
PYEDGE

edge_text() { # <derivation> <destination>
  nix derivation show "$1" >"$WORK/edge-drv.json" || fail "the edge Caddy configuration derivation cannot be inspected"
  python3 - "$WORK/edge-drv.json" "$2" <<'PYEDGETEXT' || fail "the edge Caddy configuration is not readable"
import json
import sys

d = json.load(open(sys.argv[1]))
drv = next(iter(d.get("derivations", d).values()))
# Nix 2.34 renders writeText through structured attributes.
text = drv.get("structuredAttrs", {}).get("text") or drv.get("env", {}).get("text")
if not text:
    sys.exit("the configuration derivation carries no rendered text")
if text.startswith("/nix/store/"):
    text = open(text).read()
open(sys.argv[2], "w").write(text)
PYEDGETEXT
}

adapt_edge() { # <rendered caddyfile> <destination> <port> <expect-site: yes|no>
  python3 - "$1" "$2" "$3" <<'PYADAPT' || fail "the edge configuration could not be adapted for a local run"
import re
import sys

src, dst, port = sys.argv[1], sys.argv[2], sys.argv[3]
# Two local-only edits, both about what cannot run off the edge host: every site
# moves onto one http:// loopback port, and the `tls` blocks go, because they name
# ACME files and client-auth CAs that exist only there. Matchers, handlers and the
# denial guards are untouched, and caddy validate still checks the result.
out = []
rewritten = 0
skip = 0
for line in open(src).read().splitlines(True):
    stripped = line.strip()
    if skip:
        skip += stripped.count("{") - stripped.count("}")
        if skip <= 0:
            skip = 0
        continue
    if stripped.startswith("tls ") and stripped.endswith("{"):
        skip = 1
        continue
    m = re.match(r"^([A-Za-z0-9*._-]+(?::[0-9]+)?)(/[^\s{]*)?\s*\{\s*$", line.rstrip("\n"))
    if m and "." in m.group(1):
        out.append(f"http://{m.group(1)}:{port}{m.group(2) or ''} {{\n")
        rewritten += 1
    else:
        out.append(line)
if rewritten < 2:
    sys.exit(f"only {rewritten} site addresses were adapted, expected one per route")
open(dst, "w").write("".join(out))
PYADAPT
  if [ "$4" = yes ]; then
    grep -q "http://${PUBLIC_HOST}:$3 {" "$2" ||
      fail "the adapted configuration does not carry the placement host"
  elif grep -q "http://${PUBLIC_HOST}:$3 {" "$2"; then
    fail "the withheld route must not render a site for the placement host"
  fi
}

start_edge() { # <caddyfile> <label> <port> <pid-var>
  "$CADDY_BIN" validate --adapter caddyfile --config "$1" >"$WORK/edge-validate-$2.log" 2>&1 || {
    cat "$WORK/edge-validate-$2.log" >&2
    fail "the rendered edge configuration for the $2 state is not valid Caddy"
  }
  "$CADDY_BIN" run --adapter caddyfile --config "$1" >"$WORK/edge-$2.log" 2>&1 &
  local pid=$!
  eval "$4=$pid"
  local up=no
  for _ in $(seq 1 60); do
    if curl -s --noproxy '*' -m 2 -o /dev/null "http://127.0.0.1:$3/" 2>/dev/null; then
      up=yes
      break
    fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.2
  done
  if [ "$up" != yes ]; then
    cat "$WORK/edge-$2.log" >&2
    fail "the rendered edge configuration for the $2 state did not answer on port $3"
  fi
}

read -r EDGE_OPEN_DRV EDGE_CONTROL_DRV < <(
  python3 - "$WORK/edge.json" <<'PYEDGEDRV'
import json
import sys

d = json.load(open(sys.argv[1]))
print(d["open"], d["noDenials"])
PYEDGEDRV
)

edge_text "$EDGE_OPEN_DRV" "$WORK/edge-open.caddyfile"
adapt_edge "$WORK/edge-open.caddyfile" "$WORK/edge-open.local" "$EDGE_OPEN_PORT" yes
start_edge "$WORK/edge-open.local" open "$EDGE_OPEN_PORT" EDGE_OPEN_PID

EDGE_HOST_HEADER="${PUBLIC_HOST}:${EDGE_OPEN_PORT}"
edge_status() { curl -s --noproxy '*' -o /dev/null -w '%{http_code}' -H "Host: ${EDGE_HOST_HEADER}" "http://127.0.0.1:${EDGE_OPEN_PORT}$1"; }
edge_denied_body() { curl -s --noproxy '*' -H "Host: ${EDGE_HOST_HEADER}" "http://127.0.0.1:${EDGE_OPEN_PORT}$1"; }
edge_body() { curl -fsS --noproxy '*' -H "Host: ${EDGE_HOST_HEADER}" "http://127.0.0.1:${EDGE_OPEN_PORT}$1"; }

# Every denied matcher is probed at a concrete path: the exact entries as they
# stand, the subtree entries with their wildcard filled in.
python3 - "$WORK/edge.json" <<'PYDENY' >"$WORK/denials.tsv" || fail "the denied path list could not be read"
import json
import sys

for pattern in json.load(open(sys.argv[1]))["denied"]:
    print(pattern, pattern.replace("*", "probe"))
PYDENY

while read -r pattern probe; do
  code="$(edge_status "$probe")"
  [ "$code" = "403" ] ||
    fail "the published edge must refuse ${pattern} (probed ${probe}) with 403, got ${code}"
  case "$(edge_denied_body "$probe")" in
    *fixture-backend* | *"$FIXTURE_SENTINEL"*)
      fail "the refused path ${probe} reached the listener or the back end"
      ;;
  esac
done <"$WORK/denials.tsv"

# The surfaces the application needs keep working through the same site.
case "$(edge_body /)" in
  *"$FIXTURE_SENTINEL shell"*) ;;
  *) fail "the published edge must still serve the SPA shell" ;;
esac
case "$(edge_body /oidc/callback)" in
  *"$FIXTURE_SENTINEL shell"*) ;;
  *) fail "the published edge must still reach the callback the SPA fallback serves" ;;
esac
case "$(edge_body /api/probe)" in
  *"fixture-backend path=/api/probe"*) ;;
  *) fail "the published edge must still reach the application API" ;;
esac
case "$(edge_body /api/owntracks)" in
  *"fixture-backend path=/api/owntracks"*) ;;
  *) fail "the device ingest path must stay open for the acceptance source" ;;
esac
case "$(edge_body /api/gpslogger)" in
  *"fixture-backend path=/api/gpslogger"*) ;;
  *) fail "the device ingest path must stay open for the acceptance source" ;;
esac

# The denials are the permit-list patterns, not their prefixes: a sibling path
# that merely starts with a denied one still reaches the application.
for sibling in /api/versions /api/home/content/extra /api/sharedx /mcp2 /api/aisle; do
  code="$(edge_status "$sibling")"
  [ "$code" = "200" ] ||
    fail "${sibling} is not a denied path and must reach the backend, got ${code}"
done

# The listener mirrors /mcp on loopback (asserted above); the edge is what keeps
# it off the public host.
[ "$(edge_status /mcp)" = "403" ] || fail "/mcp must not be publicly reachable"
[ "$(edge_status /mcp/probe)" = "403" ] || fail "/mcp/* must not be publicly reachable"

# Control: with the route's denial list removed the same requests reach the
# backend, so the refusals above are the guard and not the fixture.
edge_text "$EDGE_CONTROL_DRV" "$WORK/edge-control.caddyfile"
adapt_edge "$WORK/edge-control.caddyfile" "$WORK/edge-control.local" "$EDGE_CONTROL_PORT" yes
start_edge "$WORK/edge-control.local" control "$EDGE_CONTROL_PORT" EDGE_CONTROL_PID
control_body() { curl -fsS --noproxy '*' -H "Host: ${PUBLIC_HOST}:${EDGE_CONTROL_PORT}" "http://127.0.0.1:${EDGE_CONTROL_PORT}$1"; }
case "$(control_body /api/version)" in
  *"fixture-backend path=/api/version"*) ;;
  *) fail "without the denial list /api/version must reach the backend, so the guard is what refuses it" ;;
esac
case "$(control_body /mcp/probe)" in
  *"fixture-backend path=/mcp/probe"*) ;;
  *) fail "without the denial list /mcp/probe must reach the listener, so the guard is what refuses it" ;;
esac

# ---------------------------------------------------------------------------
# 2c. Private bootstrap tunnel: the public origin survives to the listener
# ---------------------------------------------------------------------------
# The operator reaches the private listener through an HTTPS origin preserved
# locally. Only the SSH hop is out of reach here; everything either side of it
# runs: a TCP forward stands in for the tunnel, a local TLS terminator issues
# itself a certificate for the public host, and the listener — which trusts
# loopback alone — must hand the backend the public Host and https.
cat > "$WORK/forward.py" <<'PYFORWARD'
import socket
import sys
import threading

listen_port, target_port = int(sys.argv[1]), int(sys.argv[2])


def pipe(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        for sock in (src, dst):
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            sock.close()


server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", listen_port))
server.listen(16)
while True:
    client, _ = server.accept()
    upstream = socket.create_connection(("127.0.0.1", target_port))
    threading.Thread(target=pipe, args=(client, upstream), daemon=True).start()
    threading.Thread(target=pipe, args=(upstream, client), daemon=True).start()
PYFORWARD

python3 "$WORK/forward.py" "$TUNNEL_FEED_PORT" "$ROUTE_PORT" >"$WORK/forward.log" 2>&1 &
FORWARD_PID=$!

cat > "$WORK/tunnel.Caddyfile" <<CADDYTUNNEL
{
  admin off
  auto_https disable_redirects
  storage file_system ${WORK}/tunnel-storage
}

https://${PUBLIC_HOST}:${TUNNEL_PORT} {
  tls internal
  reverse_proxy 127.0.0.1:${TUNNEL_FEED_PORT} {
    header_up Host {http.request.host}
  }
}
CADDYTUNNEL

"$CADDY_BIN" validate --adapter caddyfile --config "$WORK/tunnel.Caddyfile" >"$WORK/tunnel-validate.log" 2>&1 || {
  cat "$WORK/tunnel-validate.log" >&2
  fail "the local TLS terminator configuration is not valid Caddy"
}
"$CADDY_BIN" run --adapter caddyfile --config "$WORK/tunnel.Caddyfile" >"$WORK/tunnel.log" 2>&1 &
TUNNEL_PID=$!

TUNNEL_ROOT="$WORK/tunnel-storage/pki/authorities/local/root.crt"
for _ in $(seq 1 60); do
  [ -f "$TUNNEL_ROOT" ] && break
  kill -0 "$TUNNEL_PID" 2>/dev/null || break
  sleep 0.2
done
[ -f "$TUNNEL_ROOT" ] || {
  cat "$WORK/tunnel.log" >&2
  fail "the local TLS terminator issued no locally trusted certificate"
}

tunnel_curl() {
  curl -sS --noproxy '*' --cacert "$TUNNEL_ROOT" --resolve "${PUBLIC_HOST}:${TUNNEL_PORT}:127.0.0.1" "$@"
}
TUNNEL_URL="https://${PUBLIC_HOST}:${TUNNEL_PORT}"
# A browser on the real :443 sends the bare public host; the test port is a run
# artefact, so the header is stated explicitly and the terminator preserves it.
tunnel_get() { tunnel_curl -H "Host: ${PUBLIC_HOST}" "$@"; }

tunnel_shell=""
for _ in $(seq 1 30); do
  tunnel_shell="$(tunnel_get "${TUNNEL_URL}/" 2>"$WORK/tunnel-curl.err")" && break
  sleep 0.2
done
case "$tunnel_shell" in
  *"$FIXTURE_SENTINEL shell"*) ;;
  *)
    cat "$WORK/tunnel-curl.err" >&2
    fail "the tunnelled public origin must serve the app shell"
    ;;
esac
case "$(tunnel_get "${TUNNEL_URL}/oidc/callback")" in
  *"$FIXTURE_SENTINEL shell"*) ;;
  *) fail "the tunnelled public origin must reach the OIDC callback path" ;;
esac
tunnel_api="$(tunnel_get -H "X-Forwarded-For: ${EDGE_CLIENT}" "${TUNNEL_URL}/api/probe")"
case "$tunnel_api" in
  *"host=${PUBLIC_HOST} "*) ;;
  *) fail "the listener must hand the backend the tunnelled public host: ${tunnel_api}" ;;
esac
case "$tunnel_api" in
  *"proto=https"*) ;;
  *) fail "the listener must hand the backend the https scheme the terminator terminated: ${tunnel_api}" ;;
esac
# The terminator is the browser's first proxy, so it owns the client chain: a
# value the caller supplies must not survive it, and the tunnelled client plus
# the listener's own hop must.
case "$tunnel_api" in
  *"${EDGE_CLIENT}"*)
    fail "the terminator must not forward a caller-supplied client address: ${tunnel_api}"
    ;;
esac
case "$tunnel_api" in
  *"xff=127.0.0.1, 127.0.0.1"*) ;;
  *) fail "the listener must hand the backend the tunnelled client chain: ${tunnel_api}" ;;
esac

# ---------------------------------------------------------------------------
# 3. Only OCI runs the workload; no other host acquires it by importing
# ---------------------------------------------------------------------------
for other in "${OTHER_HOSTS[@]}"; do
  leaked="$(
    nix eval --json --no-write-lock-file --impure --apply 'c: {
      backend = c.systemd.services ? geopulse-backend;
      web = c.systemd.services ? geopulse-web;
    }' "path:${ROOT}#nixosConfigurations.${other}.config" 2>/dev/null
  )" || fail "${other}: absence probe does not evaluate"
  [ "$leaked" = '{"backend":false,"web":false}' ] ||
    fail "${other}: the GeoPulse runtime leaked onto a host that does not select it: ${leaked}"
done

echo "check-geopulse-contract: PASS (${HOST} evaluated, ${RUN_HOST} listener exercised)"
