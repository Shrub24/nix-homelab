#!/usr/bin/env bash
# Build-account contract: every host accepts exactly the nixbot controller's key,
# and ssh-ng's dispatch account has the trusted-user permission required for its
# remote store operations.
#
# The check is deliberately non-vacuous: the same validator that must accept the
# evaluated account must reject a copy whose authorized keys have been emptied,
# so a silently missing binding cannot pass as a satisfied contract.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOSTS=(oci-melb-1 home-forge)
export NIXBOT_PUBLIC_KEY
NIXBOT_PUBLIC_KEY="$(nix eval --raw --file "$ROOT/policy/nixbot.nix" --apply 'p: p.builderPublicKey')"

# Supports validating an unpublished upstream fix without changing flake.lock.
NIX_EVAL_ARGS=(eval --impure --json --no-write-lock-file)
if [ -n "${NIX_FLEET_OVERRIDE:-}" ]; then
  NIX_EVAL_ARGS+=(--override-input nix-fleet "$NIX_FLEET_OVERRIDE")
fi

fail() {
  echo "check-build-account-contract: $*" >&2
  exit 1
}

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
        nixbotCoordinator = cfg.config.services.nixbot.enable or false;
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
import json, os, sys

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
if keys != [os.environ["NIXBOT_PUBLIC_KEY"]]:
    sys.exit("expected exactly the nixbot controller key: %r" % keys)
if account["buildMachines"] and not account["nixbotCoordinator"]:
    sys.exit("a non-coordinator host schedules build machines")
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
done

echo "check-build-account-contract: PASS (${HOSTS[*]})"
