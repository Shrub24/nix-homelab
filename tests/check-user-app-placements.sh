#!/usr/bin/env bash
set -euo pipefail

# User-app placement contract (openspec change add-actual-memos-tududi,
# task 5.2; design VER-1).
#
# Actual Budget, Memos and tududi are placed on oci-melb-1 by aspect selection.
# Each one is wired from three places that have to agree and can drift apart
# without any of them failing on its own: the route in policy/web-services.nix
# (port, exposure mode), the service that listens (its own port and bind
# address), and the identity-contract client the application logs in through. This
# check
# reads the evaluated configuration, not source text, and pins those
# relationships:
#
#   - a route's port is the port the service really listens on, and its
#     exposure mode matches the socket (a loopback listener behind the edge is
#     `direct`; anything wider would make `direct` dial the wrong place);
#   - each application has an identity-contract client of its own name, and the
#     route is flagged as an application-OIDC consumer with the Cloudflare Access
#     gate off, because the sync clients cannot carry a session;
#   - each state path is covered by state-backups and a WAL-mode sqlite database
#     is captured through an export rather than copied while writable;
#   - tududi's container keeps its state on /srv/data, owned by the uid the
#     image runs as, and its image reference carries both tag and digest.
#
# It is evaluation-only. The artifacts themselves are proven where they run.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "check-user-app-placements: $*" >&2
  exit 1
}

HOST="oci-melb-1"
OTHER_HOSTS=(home-forge la-admin-1)

probe_selected="$(
  cat <<'NIX'
c: let
  routes = c.repo.web.hosts.oci-melb-1.services;
  clients = c.services.identity.oidc.clients;
  container = c.virtualisation.oci-containers.containers.tududi or null;
  unit = c.systemd.services.podman-tududi or null;
in {
  actualEnabled = c.services.actual.enable or false;
  memosEnabled = c.services.memos.enable or false;
  tududiEnabled = container != null;

  actualSettings = c.services.actual.settings or { };
  memosSettings = c.services.memos.settings or { };
  memosOpenFirewall = c.services.memos.openFirewall or false;
  actualUser = c.systemd.services.actual.serviceConfig.User or null;
  memosUser = c.systemd.services.memos.serviceConfig.User or null;

  tududiContainer = if container == null then null else {
    inherit (container) image ports volumes environmentFiles environment;
  };
  tududiUnitMounts = if unit == null then null else (unit.unitConfig.RequiresMountsFor or null);
  tmpfiles = c.systemd.tmpfiles.rules;

  memosIdp = let
    names = builtins.filter (n: builtins.match "memos-idp-.*\\.json" n != null) (builtins.attrNames c.sops.templates);
    t = if names == [ ] then null else c.sops.templates.${builtins.head names};
  in
    if t == null then null else {
      inherit (t) path owner group mode content;
      restartUnits = t.restartUnits or [ ];
    };
  memosAfter = c.systemd.services.memos.after or [ ];
  memosWants = c.systemd.services.memos.wants or [ ];
  memosLoadCredential = c.systemd.services.memos.serviceConfig.LoadCredential or [ ];
  memosBindReadOnly = c.systemd.services.memos.serviceConfig.BindReadOnlyPaths or [ ];
  tududiEnvContent = c.sops.templates."tududi.environment".content or "";
  tududiAdminEmailOption = c.services.tududi ? adminEmail;

  routes = builtins.mapAttrs (_: r: {
    exposureMode = r.exposureMode;
    upstream = r.upstream;
    publicUrl = r.publicUrl;
    category = r.category;
    declarePublic = r.declarePublic;
    originProvider = r.origin.provider or null;
    originPort = r.origin.port or null;
    requireAccess = r.access.requireCloudflareAccess;
    oidcEnabled = r.access.oidc.enabled;
  }) (builtins.intersectAttrs { actual = 1; memos = 1; tududi = 1; } routes);

  clients = builtins.mapAttrs (_: cl: { inherit (cl) clientId; })
    (builtins.intersectAttrs { actual = 1; memos = 1; tududi = 1; } clients);

  backups = builtins.mapAttrs (_: b: {
    inherit (b) mode paths exclude exportPaths prepareCommands;
  }) (builtins.intersectAttrs { actual = 1; memos = 1; tududi = 1; } c.services.state-backups.services);
}
NIX
)"

json="$(
  nix eval --json --no-write-lock-file --apply "$probe_selected" \
    "path:.#nixosConfigurations.${HOST}.config" 2>/dev/null
)" || fail "${HOST}: placement probe does not evaluate"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
printf '%s' "$json" >"$tmp"

python3 - "$tmp" <<'PYEOF' || fail "${HOST}: user-app placement contract violated"
import json, re, sys

got = json.load(open(sys.argv[1]))
errs = []

for app in ("actual", "memos", "tududi"):
    if not got[f"{app}Enabled"]:
        errs.append(f"{app}: selected aspect did not enable the service on oci-melb-1")

routes, clients, backups = got["routes"], got["clients"], got["backups"]

for app in ("actual", "memos", "tududi"):
    r = routes.get(app)
    if r is None:
        errs.append(f"{app}: no route in the web policy")
        continue
    # Placement: the route belongs to this host, publicly, behind no edge gate.
    if r["originProvider"] != "oci-melb-1":
        errs.append(f"{app}: route provider {r['originProvider']!r}, want oci-melb-1")
    if r["requireAccess"] is not False:
        errs.append(f"{app}: requireCloudflareAccess must be false (clients cannot carry an Access session)")
    if r["oidcEnabled"] is not True:
        errs.append(f"{app}: the route must be flagged an application-OIDC consumer")
    if r["declarePublic"] is not True:
        errs.append(f"{app}: the route must be published")
    # A loopback listener behind the edge is the only socket `direct` can dial.
    if r["exposureMode"] != "direct":
        errs.append(f"{app}: exposureMode {r['exposureMode']!r}, want direct for a loopback listener")
    if r["upstream"] != f"http://127.0.0.1:{r['originPort']}":
        errs.append(f"{app}: edge upstream {r['upstream']!r} does not dial loopback on the route port {r['originPort']}")
    # The identity contract carries a client of the same name. Its endpoints belong to the
    # client rather than to this check: the issuer URL's shape is the provider's grammar, so
    # pinning a path here would re-encode Kanidm's or Authentik's layout instead of our
    # contract.
    if clients.get(app) is None:
        errs.append(f"{app}: no identity-contract client")

# Actual: the listener, its bind address and its OpenID block agree with the route.
actual = got["actualSettings"]
r = routes.get("actual", {})
if actual.get("port") != r.get("originPort"):
    errs.append(f"actual: listens on {actual.get('port')!r}, route dials {r.get('originPort')!r}")
if actual.get("hostname") != "127.0.0.1":
    errs.append(f"actual: bind address {actual.get('hostname')!r}, want loopback")
methods = actual.get("allowedLoginMethods") or []
if actual.get("loginMethod") != "openid" or "password" in methods or "openid" not in methods:
    errs.append(
        "actual: the provider must be the only interactive sign-in method, so the "
        f"local credential is not offered: {actual.get('loginMethod')!r} {methods!r}"
    )
openid = actual.get("openId", {})
if openid.get("client_id") != "actual":
    errs.append(f"actual: openId client_id {openid.get('client_id')!r}")
if not re.match(r"^https://[^/]+$", openid.get("server_hostname", "")) or openid.get("server_hostname") != r.get("publicUrl"):
    errs.append(f"actual: server_hostname {openid.get('server_hostname')!r} must be the route's public origin")
secret = openid.get("client_secret", {})
if not (isinstance(secret, dict) and secret.get("_secret")):
    errs.append("actual: the client secret must be bound by path (_secret), never inline")

# Memos: same shape; plus the instance URL and the module's firewall trap.
memos = got["memosSettings"]
r = routes.get("memos", {})
if memos.get("MEMOS_PORT") != r.get("originPort"):
    errs.append(f"memos: listens on {memos.get('MEMOS_PORT')!r}, route dials {r.get('originPort')!r}")
if memos.get("MEMOS_ADDR") != "127.0.0.1":
    errs.append(f"memos: bind address {memos.get('MEMOS_ADDR')!r}, want loopback")
if memos.get("MEMOS_INSTANCE_URL") != r.get("publicUrl"):
    errs.append(f"memos: MEMOS_INSTANCE_URL {memos.get('MEMOS_INSTANCE_URL')!r} is not the route's public URL")
if memos.get("MEMOS_DRIVER") != "sqlite":
    errs.append(f"memos: driver {memos.get('MEMOS_DRIVER')!r}, want sqlite")
if got["memosOpenFirewall"]:
    errs.append("memos: openFirewall must stay off (the module's firewall branch reads an option it never defines)")

# tududi: one pinned container whose published port is loopback-only and equals
# the route's, state on /srv/data owned by the image's runtime uid.
ctr = got["tududiContainer"]
r = routes.get("tududi", {})
if ctr:
    image = ctr["image"]
    if not re.match(r"^[^@:]+(:[^@/]+)?:[^@/]+@sha256:[0-9a-f]{64}$", image):
        errs.append(f"tududi: image {image!r} must carry both a tag and a sha256 digest")
    want_port = f"127.0.0.1:{r.get('originPort')}:{r.get('originPort')}"
    if ctr["ports"] != [want_port]:
        errs.append(f"tududi: published ports {ctr['ports']!r}, want exactly {[want_port]!r} (loopback only)")
    mounts = sorted(ctr["volumes"])
    want_mounts = sorted(f"/srv/data/tududi/{d}:/app/{d}" for d in ("db", "uploads", "backups"))
    if mounts != want_mounts:
        errs.append(f"tududi: mounts {mounts!r}, want {want_mounts!r}")
    env = ctr["environment"]
    if env.get("BASE_URL") != r.get("publicUrl"):
        errs.append(f"tududi: BASE_URL {env.get('BASE_URL')!r} is not the route's public URL")
    if env.get("TUDUDI_ALLOWED_ORIGINS") != r.get("publicUrl"):
        errs.append(f"tududi: TUDUDI_ALLOWED_ORIGINS {env.get('TUDUDI_ALLOWED_ORIGINS')!r} is not the route's public URL")
    if env.get("TUDUDI_TRUST_PROXY") != "true":
        errs.append("tududi: TUDUDI_TRUST_PROXY must be true behind the edge")
    if env.get("PORT") != str(r.get("originPort")):
        errs.append(f"tududi: PORT {env.get('PORT')!r} does not match the route port {r.get('originPort')!r}")
    if "OIDC_CLIENT_SECRET" in env or "TUDUDI_SESSION_SECRET" in env:
        errs.append("tududi: secrets must be delivered through the rendered environment file, not the container environment")
    if "TUDUDI_OIDC_SECRET_ENCRYPTION_KEY" in env:
        errs.append("tududi: TUDUDI_OIDC_SECRET_ENCRYPTION_KEY must stay unset (derived from the session secret upstream)")
    if not ctr["environmentFiles"]:
        errs.append("tududi: no rendered environment file bound")
    # State ownership: the entrypoint drops to uid 1001, so every state directory is theirs.
    for d in ("", "/db", "/uploads", "/backups"):
        if f"d /srv/data/tududi{d} 0750 1001 1001 - -" not in got["tmpfiles"]:
            errs.append(f"tududi: /srv/data/tududi{d} is not created 0750 1001:1001")
    if got["tududiUnitMounts"] is None or "/srv/data/tududi" not in str(got["tududiUnitMounts"]):
        errs.append("tududi: the unit must require the /srv/data mount before it starts")

# Memos loads its identity provider from /etc/secrets at startup. That directory
# is shared and stays root-owned, so the unit must receive the provider as its
# own credential and bind only the credential directory over /etc/secrets. The
# rendered source stays root-owned under sops' default path, and its endpoints
# are the contract's rather than literals.
idp = got["memosIdp"]
mc = clients.get("memos", {})
provider = idp["path"].rsplit("/", 1)[-1] if idp else ""
if idp is None:
    errs.append("memos: no rendered identity-provider file matching memos-idp-*.json")
else:
    if idp["path"].startswith("/etc/secrets/"):
        errs.append(f"memos: rendered source {idp['path']!r} must stay outside the shared /etc/secrets directory")
    # sops-nix leaves owner/group unset for root; either way the render is not memos-owned.
    if idp["owner"] not in (None, "root") or idp["group"] not in (None, "root") or idp["mode"] != "0400":
        errs.append(f"memos: rendered source must stay root-owned 0400, got {(idp['owner'], idp['group'], idp['mode'])!r}")
    # The bind mount exposes the credential directory to the unit, so every file in it has
    # to be one this module rendered. What the module declares is its own business; that the
    # directory cannot hold anything else is the property worth guarding.
    creds = got["memosLoadCredential"]
    cred_names = [entry.split(":", 1)[0] for entry in creds]
    sources = [entry.split(":", 1)[1] for entry in creds if ":" in entry]
    provider_creds = [name for name in cred_names if name.startswith("memos-idp-")]
    if provider_creds != [provider]:
        errs.append(f"memos: provider credentials {provider_creds!r}, want exactly the rendered {provider!r}")
    if len(cred_names) != len(set(cred_names)):
        errs.append(f"memos: duplicate credential names {cred_names!r}")
    if len(sources) != len(creds) or any(not s.startswith("/run/secrets/rendered/") for s in sources):
        errs.append(f"memos: every credential must load a rendered sops file, got {creds!r}")
    if got["memosBindReadOnly"] != ["/run/credentials/memos.service:/etc/secrets"]:
        errs.append(f"memos: BindReadOnlyPaths {got['memosBindReadOnly']!r}; want the credential directory over /etc/secrets")
    if any("%" in b for b in got["memosBindReadOnly"]):
        errs.append("memos: BindReadOnlyPaths must use a literal path; systemd rejects %d here")
    if "memos.service" not in idp["restartUnits"]:
        errs.append("memos: a rotated provider secret must restart the unit (providers load only at startup)")
    try:
        doc = json.loads(re.sub(r"<SOPS:[^>]*>", "x", idp["content"]))
        oauth = doc["config"]["oauth2Config"]
        if oauth.get("clientId") != mc.get("clientId") or doc.get("uid") != mc.get("clientId"):
            errs.append(
                f"memos: provider id/clientId {(doc.get('uid'), oauth.get('clientId'))!r} "
                f"is not the contract's {mc.get('clientId')!r}"
            )
        if doc.get("type") != "OAUTH2":
            errs.append(f"memos: provider type {doc.get('type')!r}, want OAUTH2")
    except (ValueError, KeyError) as e:
        errs.append(f"memos: provider file is not the documented shape: {e!r}")
    if not re.search(r'"clientSecret":\s*"<SOPS:[0-9a-f]+:PLACEHOLDER>"', idp["content"]):
        errs.append("memos: clientSecret must be a sops placeholder, never an inline value")

# tududi's bootstrap address is app-local secret material, not Nix configuration.
if got["tududiAdminEmailOption"]:
    errs.append("tududi: services.tududi.adminEmail was retired; the address belongs to the secret template")
if "TUDUDI_USER_EMAIL=" not in got["tududiEnvContent"]:
    errs.append("tududi: the rendered environment carries no TUDUDI_USER_EMAIL")

# Backups: all three registered; each live WAL-mode database is exported, and its
# live files are not part of any raw path.
want_db = {
    "actual": ("/srv/data/actual/server-files/account.sqlite", "/srv/data/state-backups/actual/account.sqlite"),
    "memos": ("/srv/data/memos/memos_prod.db", "/srv/data/state-backups/memos/memos_prod.db"),
    "tududi": ("/srv/data/tududi/db/production.sqlite3", "/srv/data/state-backups/tududi/production.sqlite3"),
}
for app, (live, export) in want_db.items():
    b = backups.get(app)
    if b is None:
        errs.append(f"{app}: not registered with state-backups")
        continue
    if b["mode"] != "export":
        errs.append(f"{app}: backup mode {b['mode']!r}, want export")
    if export not in b["exportPaths"]:
        errs.append(f"{app}: the exported database {export!r} is not captured: {b['exportPaths']!r}")
    for p in b["paths"]:
        if live == p or live.startswith(p.rstrip("/") + "/"):
            # The directory holds the live file, so the file and its WAL must be excluded.
            for suffix in ("", "-wal", "-shm"):
                if live + suffix not in b["exclude"]:
                    errs.append(f"{app}: raw path {p!r} contains the live database but {live + suffix!r} is not excluded")
    if not any("sqlite3" in c and ".backup" in c and live in c for c in b["prepareCommands"]):
        errs.append(f"{app}: no sqlite3 .backup export of {live!r} runs before the capture")
    if not any("-readonly" in c for c in b["prepareCommands"] if "sqlite3" in c):
        errs.append(f"{app}: the export must open the database read-only, or a missing file is silently created empty")

if errs:
    print("\n".join(f"  {e}" for e in errs), file=sys.stderr)
    sys.exit(1)
PYEOF

# The aspects are placements, not baseline: a host that does not select them
# must stay free of all three.
for other in "${OTHER_HOSTS[@]}"; do
  leaked="$(
    nix eval --json --no-write-lock-file --apply 'c: {
      actual = c.services.actual.enable or false;
      memos = c.services.memos.enable or false;
      tududi = c.virtualisation.oci-containers.containers ? tududi;
    }' "path:.#nixosConfigurations.${other}.config" 2>/dev/null
  )" || fail "${other}: leak probe does not evaluate"
  [ "$leaked" = '{"actual":false,"memos":false,"tududi":false}' ] ||
    fail "${other}: user-app placements leaked onto a host that does not select them: ${leaked}"
done

echo "check-user-app-placements: PASS (${HOST})"
