#!/usr/bin/env bash
# Build-account contract: every host accepts the canonical CI coordinator key,
# and ssh-ng's dispatch account has the trusted-user permission required for its
# remote store operations.
#
# The check is deliberately non-vacuous: the same validator that must accept the
# evaluated account must reject a copy whose authorized keys have been emptied,
# so a silently missing binding cannot pass as a satisfied contract.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOSTS=(oci-melb-1 la-admin-1 home-forge)

# The canonical coordinator key's fingerprint, from nix-fleet's
# fleet.ci.sshPublicKey. Pinning it here is the anchor that lets this check
# fail: a rotated or substituted key changes it and demands a deliberate update.
readonly COORDINATOR_FINGERPRINT="SHA256:fDt1gCUVVZpK2y6HPV/jTuZiuR8z3nM1+3oYYy6GpCs"

# Supports validating an unpublished upstream fix without changing flake.lock.
NIX_EVAL_ARGS=(eval --impure --json --no-write-lock-file)
if [ -n "${NIX_FLEET_OVERRIDE:-}" ]; then
  NIX_EVAL_ARGS+=(--override-input nix-fleet "$NIX_FLEET_OVERRIDE")
fi

fail() {
  echo "check-build-account-contract: $*" >&2
  exit 1
}

KEY_FILE="$(mktemp)"
trap 'rm -f "$KEY_FILE"' EXIT

# Projection of the evaluated account, plus a mutated copy with no authorized
# key, from one evaluation so both come from the same configuration.
projection() { # $1 host
  nix "${NIX_EVAL_ARGS[@]}" "$ROOT#nixosConfigurations.$1" --apply '
    cfg: let
      project = cfg: let
        u = cfg.config.users.users.nixbuild;
        accountName = cfg.config.services.build-account.name;
      in {
        inherit (u) isSystemUser group shell home createHome extraGroups;
        inherit accountName;
        keys = u.openssh.authorizedKeys.keys;
        trustedUsers = cfg.config.nix.settings.trusted-users;
        buildMachines = builtins.length cfg.config.nix.buildMachines;
      };
      real = cfg;
    in {
      real = project real;
      mutated = project (real.extendModules {
        modules = [ ({ lib, ... }: { users.users.nixbuild.openssh.authorizedKeys.keys = lib.mkForce [ ]; }) ];
      });
    }
  '
}

# Accepts the contract, or prints why it does not hold.
validate() {
  python3 -c '
import json, sys

account = json.load(sys.stdin)
keys = account["keys"]
if account["isSystemUser"] is not True:
    sys.exit("account is not a system user")
if account["group"] != "nixbuild":
    sys.exit("account group is %r, expected nixbuild" % account["group"])
if account["home"] != "/var/lib/nixbuild":
    sys.exit("account home is %r" % account["home"])
if account["createHome"] is not True:
    sys.exit("account home is not created")
if not account["shell"] or "bash" not in account["shell"]:
    sys.exit("account shell %r is not a working shell for ssh-ng" % account["shell"])
if account["extraGroups"]:
    sys.exit("account carries extra groups: %r" % account["extraGroups"])
if account["accountName"] not in account["trustedUsers"]:
    sys.exit("dispatch account %r is absent from trusted-users %r" % (account["accountName"], account["trustedUsers"]))
if len(keys) != 1:
    sys.exit("authorized keys are %r, expected exactly the coordinator key" % keys)
if not keys[0].startswith("ssh-ed25519 "):
    sys.exit("authorized key is not an ed25519 key: %r" % keys[0])
if account["buildMachines"]:
    sys.exit("host schedules %d build machines; CI is the build path" % account["buildMachines"])
print("ok")
'
}

for host in "${HOSTS[@]}"; do
  json="$(projection "$host")" || fail "$host: build account does not evaluate"
  real="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["real"]))')"
  mutated="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["mutated"]))')"

  result="$(printf '%s' "$real" | validate 2>&1)" || fail "$host: $result"
  [ "$result" = ok ] || fail "$host: $result"

  # Non-vacuity: the validator must reject an account without its key or daemon trust.
  if printf '%s' "$mutated" | validate >/dev/null 2>&1; then
    fail "$host: validator accepted an account with no authorized key"
  fi
  untrusted="$(printf '%s' "$real" | python3 -c 'import json,sys; account=json.load(sys.stdin); account["trustedUsers"]=[u for u in account["trustedUsers"] if u != account["accountName"]]; print(json.dumps(account))')"
  if printf '%s' "$untrusted" | validate >/dev/null 2>&1; then
    fail "$host: validator accepted a dispatch account absent from trusted-users"
  fi

  # The authorized key must be the canonical coordinator key.
  printf '%s' "$real" | python3 -c 'import json,sys; print(json.load(sys.stdin)["keys"][0])' >"$KEY_FILE" ||
    fail "$host: authorized key is not readable"
  fingerprint="$(ssh-keygen -lf "$KEY_FILE" | awk '{print $2}')" ||
    fail "$host: authorized key is not a valid public key"
  [ "$fingerprint" = "$COORDINATOR_FINGERPRINT" ] ||
    fail "$host: authorized key fingerprint $fingerprint is not the canonical coordinator key"
done

echo "check-build-account-contract: PASS (${HOSTS[*]})"
