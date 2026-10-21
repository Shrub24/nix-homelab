#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Evaluation only; these sentinel values are never decrypted or used to start a service.
cat >"$tmp/homarr.yaml" <<'EOF'
auth_secret: "test-only-not-a-secret"
secret_encryption_key: "test-only-not-a-secret"
homarr:
  client_secret: "test-only-not-a-secret"
EOF

# The withheld-posture control: a copy of the tree whose Homarr route says
# publish = false. repo.web is read-only, so this is the only way to exercise the
# recovery posture the runbook describes.
CONTROL="$(mktemp -d "$tmp/control.XXXXXX")"
tar -C "$ROOT" \
  --exclude=.git --exclude=.jj --exclude=./opentofu \
  --exclude=.qmd --exclude=.direnv --exclude=.tmp --exclude=.pi \
  --exclude=.ruff_cache \
  -cf - . | tar -C "$CONTROL" -xf -
python3 - "$CONTROL" <<'PYWITHHELD' || { echo "the withheld-route control mutation failed" >&2; exit 1; }
import sys

path = sys.argv[1] + "/policy/web-services.nix"
src = open(path).read()
anchor = "        homarr = {"
start = src.index(anchor)
end = src.index("        inbox-zero = {", start)
block = src[start:end]
insert = '          publish = false;\n'
if "publish =" in block:
    sys.exit("the homarr route already declares publish; the control anchor drifted")
mutated = block.replace(anchor + "\n", anchor + "\n" + insert, 1)
open(path, "w").write(src[:start] + mutated + src[end:])
PYWITHHELD

cat >"$tmp/probe.nix" <<EOF
let
  repo = builtins.getFlake "path:$ROOT";
  fixture = builtins.toPath "$tmp/homarr.yaml";
  # The login posture is derived from the route's publish flag (D-104): a
  # published route serves OIDC only, a withheld one keeps credentials as the
  # way back in. The probes force the flag rather than an application option.
  mkHomarr = publish: repo.nixosConfigurations.oci-melb-1.extendModules {
    # oci-melb-1 selects the homarr aspect, so the module is already part of
    # this configuration; importing it again would re-declare its options.
    modules = [
      ({ lib, ... }:
        {
          services.homarr.secretFiles.host = fixture;
          services.homarr.secretFiles.oidc = fixture;
        }
        // lib.optionalAttrs (publish != null) {
          repo.web.hosts.oci-melb-1.services.homarr.publish = lib.mkForce publish;
        })
    ];
  };
  defaults = mkHomarr null;
  normal = (mkHomarr null).config;
  # A withheld route cannot be forced: repo.web is read-only. The recovery posture
  # is therefore exercised on a throwaway copy of the tree whose policy withholds
  # it, which is the same edit an operator makes to reopen the credentials login.
  withheld = builtins.getFlake "path:${CONTROL}";
  container = normal.virtualisation.oci-containers.containers.homarr;
  route = normal.repo.web.catalog.homarr;
  routeData = normal.repo.web.hosts.oci-melb-1.services.homarr;
  backup = normal.services.state-backups.services.homarr;
  provider = repo.nixosConfigurations.la-admin-1.config;
  kanidmClient = provider.services.kanidm.provision.systems.oauth2.homarr;
  endpoint = provider.repo.web.catalog.homarr.endpoint;
  privateBase = "https://" + endpoint.host + ":" + toString endpoint.port;
  privateCallback = privateBase + "/api/auth/callback/oidc";
in {
  homarrEnabled = normal.services.homarr.enable;
  # A host that says nothing about the option tree keeps the published posture:
  # withholding is written down on the policy route, never assumed.
  declaresBootstrapOption = defaults.options.services.homarr ? credentialsBootstrap;
  route = {
    inherit (route) exposureMode upstreamPort publicUrl declarePublic;
    publish = routeData.publish or true;
    inherit (route.access) requireCloudflareAccess;
    oidcEnabled = route.access.oidc.enabled;
  };
  container = {
    inherit (container) image ports volumes environment environmentFiles;
    unitMounts = normal.systemd.services.podman-homarr.unitConfig.RequiresMountsFor;
    unitWants = normal.systemd.services.podman-homarr.wants;
    unitAfter = normal.systemd.services.podman-homarr.after;
  };
  environmentFile = {
    inherit (normal.sops.templates."homarr.environment") owner group mode restartUnits;
  };
  normalEnvironment = normal.sops.templates."homarr.environment".content;
  withheldEnvironment =
    (withheld.nixosConfigurations.oci-melb-1.extendModules {
      modules = [
        ({ ... }: {
          services.homarr.secretFiles.host = fixture;
          services.homarr.secretFiles.oidc = fixture;
        })
      ];
    }).config.sops.templates."homarr.environment".content;
  sqliteRestoreToolAvailable = builtins.any (package: (package.pname or "") == "sqlite") normal.environment.systemPackages;
  backup = {
    inherit (backup) mode paths exclude exportPaths prepareCommands cleanupCommands;
  };
  kanidmRedirectUris = kanidmClient.originUrl;
  inherit privateBase privateCallback;
}
EOF

json="$(nix eval --json --impure --no-write-lock-file --file "$tmp/probe.nix")" || {
  echo "check-homarr-contract: evaluated Homarr configuration is unavailable" >&2
  exit 1
}
printf '%s' "$json" >"$tmp/result.json"

python3 - "$tmp/result.json" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    got = json.load(handle)
errors = []

if got["homarrEnabled"] is not True:
    errors.append("the selected Homarr aspect must enable the service")
if got["declaresBootstrapOption"]:
    errors.append("the retired credentialsBootstrap option is back; the posture derives from publish")
route = got["route"]

def route_errors(candidate):
    found = []
    if candidate["exposureMode"] != "tailscale-serve":
        found.append("the route must use the provider's Tailscale Serve front")
    if candidate["upstreamPort"] != 7575:
        found.append(f"route port is {candidate['upstreamPort']!r}, want 7575")
    if candidate["requireCloudflareAccess"] is not False:
        found.append("Cloudflare Access must stay off; Homarr owns browser authentication")
    if candidate["oidcEnabled"] is not True:
        found.append("the route must declare its application OIDC consumer")
    if candidate["declarePublic"] is not True:
        found.append("the withheld route must retain its public identity for eventual release")
    if candidate["publish"] is not True:
        found.append("the route is published: Homarr is the fleet dashboard and its OIDC login is the gate")
    return found

errors.extend(route_errors(route))
mutated_route = dict(route)
mutated_route["publish"] = False
if not route_errors(mutated_route):
    errors.append("mutation control failed to reject a withheld dashboard route")

container = got["container"]
if not re.search(r"@sha256:[0-9a-f]{64}$", container["image"]):
    errors.append("container image must be pinned by a full registry digest")
if container["ports"] != ["127.0.0.1:7575:7575"]:
    errors.append(f"container is not loopback-only on 7575: {container['ports']!r}")
if container["volumes"] != ["/srv/data/homarr:/appdata"]:
    errors.append(f"unexpected Homarr state mount: {container['volumes']!r}")
if len(container["environmentFiles"]) != 1 or not container["environmentFiles"][0].endswith("/homarr.environment"):
    errors.append("secret-bearing Homarr variables must come from one rendered environment file")
if set(container["environment"]) != {"PUID", "PGID"}:
    errors.append("the container's literal environment must contain only its non-secret UID/GID values")
if container["environment"].get("PUID") != "1001" or container["environment"].get("PGID") != "1001":
    errors.append("Homarr's persistent state owner must match its configured PUID/PGID")
if "/srv/data/homarr" not in container["unitMounts"]:
    errors.append("podman-homarr must require the persistent data mount")
environment_file = got["environmentFile"]
if (environment_file["owner"], environment_file["group"], environment_file["mode"]) != ("root", "root", "0400"):
    errors.append("the rendered secret environment must be root-owned and mode 0400")
if "podman-homarr.service" not in environment_file["restartUnits"]:
    errors.append("secret rotation must restart the Homarr container")

normal_env = got["normalEnvironment"]
withheld_env = got["withheldEnvironment"]
if got["sqliteRestoreToolAvailable"] is not True:
    errors.append("the host must provide the SQLite CLI used to verify staged restores")
for name in ("AUTH_SECRET", "SECRET_ENCRYPTION_KEY", "AUTH_OIDC_ISSUER", "AUTH_OIDC_CLIENT_ID", "AUTH_OIDC_CLIENT_SECRET"):
    if not any(line.startswith(name + "=") for line in normal_env.splitlines()):
        errors.append(f"rendered environment is missing {name}")
if "AUTH_PROVIDERS=oidc" not in normal_env:
    errors.append("steady state must enable OIDC without the credentials fallback")
if "AUTH_PROVIDERS=credentials,oidc" not in withheld_env:
    errors.append("a withheld route must keep credentials beside OIDC as the way back in")
def scope_errors(env_text):
    found = []
    values = [
        line.split("=", 1)[1]
        for line in env_text.splitlines()
        if line.startswith("AUTH_OIDC_SCOPE_OVERWRITE=")
    ]
    if len(values) != 1:
        found.append(f"the rendered environment must set AUTH_OIDC_SCOPE_OVERWRITE exactly once, got {len(values)}")
        return found
    value = values[0]
    # This file is a container env file: its parser keeps quotes as part of the
    # value, so a quoted list reaches Kanidm as scope='"openid email profile"'
    # and is rejected with invalid_scope. The value, not the line's text, is
    # what the identity provider sees.
    # `groups_name` is requested so Kanidm emits the group claim Homarr joins
    # administration from; the unquoted form is what keeps Kanidm's scope regex
    # happy, so the assertion pins the value and the quoting trap together.
    if value != "openid email profile groups_name":
        found.append(
            "AUTH_OIDC_SCOPE_OVERWRITE must be the unquoted list 'openid email profile groups_name', "
            f"got {value!r}"
        )
    return found

errors.extend(scope_errors(normal_env))
errors.extend(scope_errors(withheld_env))
if not scope_errors('AUTH_OIDC_SCOPE_OVERWRITE="openid email profile groups_name"'):
    errors.append("mutation control failed to reject a quoted OIDC scope list")
# Group membership is authoritative from the identity provider (D-103): the
# `groups` claim decides administration, so the local manager must be off and the
# claim attribute named.
if "AUTH_OIDC_GROUPS_LOCAL_MANAGEMENT=false" not in normal_env:
    errors.append("OIDC group membership must come from the provider, not local management")
if "AUTH_OIDC_GROUPS_ATTRIBUTE=groups" not in normal_env:
    errors.append("the group claim attribute must be named `groups`")
if "AUTH_OIDC_ENABLE_DANGEROUS_CREDENTIALS_LINKING=false" not in normal_env:
    errors.append("dangerous automatic OIDC credential linking must remain disabled")
if "BASE_URL=https://home.shrublab.xyz" not in normal_env:
    errors.append("steady state BASE_URL must use Homarr's canonical public origin")
if f"BASE_URL={got['privateBase']}" not in withheld_env:
    errors.append("a withheld route's BASE_URL must use the private Tailscale Serve origin")
if "NEXTAUTH_URL=" in normal_env or "NEXTAUTH_URL=" in withheld_env:
    errors.append("a fixed NEXTAUTH_URL would override the request-specific OIDC callback")

def backup_errors(backup):
    found = []
    if backup["mode"] != "export":
        found.append("mode must be export")
    if backup["paths"] != ["/srv/data/homarr"]:
        found.append("only /srv/data/homarr may be captured raw")
    if "/srv/data/homarr/db" not in backup["exclude"]:
        found.append("the live SQLite database directory must be excluded from raw capture")
    if backup["exportPaths"] != ["/srv/data/state-backups/homarr/db.sqlite"]:
        found.append("the SQLite export path is incorrect")
    if not any("sqlite3 -readonly /srv/data/homarr/db/db.sqlite" in command and ".backup" in command for command in backup["prepareCommands"]):
        found.append("the live database must be exported through sqlite3's backup API")
    if any("/srv/data/homarr/db" in path for path in backup["paths"]):
        found.append("the database must not be captured raw")
    return found

backup = got["backup"]
errors.extend(backup_errors(backup))
mutated = dict(backup)
mutated["paths"] = backup["paths"] + ["/srv/data/homarr/db"]
if not backup_errors(mutated):
    errors.append("mutation control failed to reject raw database capture")

uris = got["kanidmRedirectUris"]
private = got["privateCallback"]
expected_public = "https://home.shrublab.xyz/api/auth/callback/oidc"
if not isinstance(uris, list) or uris != [expected_public, private]:
    errors.append(f"Kanidm callback list must include the canonical and Tailscale Serve URLs; got {uris!r}")
if not private.startswith("https://oci-melb-1.") or not private.endswith(":7575/api/auth/callback/oidc"):
    errors.append(f"private callback is not the OCI Tailscale Serve URL: {private!r}")

if errors:
    print("check-homarr-contract: FAIL", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    sys.exit(1)
print("check-homarr-contract: PASS")
PY
