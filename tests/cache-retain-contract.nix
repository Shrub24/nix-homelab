# The main-push retention contract: what the effect claims, and what its script
# does when a push or the substitution check fails. niks3 and the Nix CLI are
# stubbed, so no live cache is touched.
{
  config,
  lib,
  pkgs,
}:
let
  output = branch: tag: config.flake.herculesCI { primaryRepo = { inherit branch tag; }; };
  main = output "main" null;
  effect = main.onPush.default.outputs.effects.cache-retain;
  x86 = config.flake.packages.x86_64-linux.cache-root;
  arm = config.flake.packages.aarch64-linux.cache-root;
  route = config.flake.nixosConfigurations.home-forge.config.repo.web.catalog.nixbot;
  cache = config.flake.nixosConfigurations.oci-melb-1.config.services.niks3-cache;
  provider = config.flake.nixosConfigurations.oci-melb-1.config.services.niks3.oidc.providers.nixbot;
  # The issuer the cache trusts must be the one the minting service announces, so
  # the two are compared against each other rather than against a literal.
  mintedIssuer = "https://${route.subdomain}.${route.primaryDomain}";
  # The name the effect is evaluated under, as nixbot derives it: the onPush job
  # then the effect attribute path.
  pushJob = lib.head (builtins.attrNames main.onPush);
  effectName = lib.head (builtins.attrNames (main.onPush.${pushJob}.outputs.effects));
  claimedEffect = "${pushJob}.${effectName}";
  rule = builtins.head provider.rules;
  # The token carries exactly the fleet's identity; any dimension left unbound
  # would admit a different repository, ref or effect.
  boundDimensions = [
    "repository"
    "ref"
    "event"
    "effect"
  ];
in
assert lib.assertMsg (
  builtins.fromJSON effect.idTokenAudiences == [ cache.cacheUrl ]
) "cache-retain must present the cache's own audience";
assert lib.assertMsg (provider.jwksUrl == "${mintedIssuer}/.well-known/jwks.json")
  "the cache must fetch nixbot's keys without discovery, so a coordinator outage cannot stop it starting";
assert lib.assertMsg (
  provider.issuer == mintedIssuer
  && provider.audience == cache.cacheUrl
  && builtins.length provider.rules == 1
  && rule.scopes == [ "write" ]
  && rule.pins == [ "nix-homelab-main-*" ]
  && builtins.all (name: rule.boundClaims ? ${name}) boundDimensions
  && rule.boundClaims.effect == [ claimedEffect ]
) "the cache must trust only nixbot, for homelab's main push reconciliation and its pins";
pkgs.runCommandLocal "cache-retain-contract"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.python3
    ];
    effectScript = pkgs.writeText "cache-retain-script" (
      builtins.unsafeDiscardStringContext effect.effectScript
    );
    nixbotToml = ../nixbot.toml;
    x86Root = builtins.unsafeDiscardStringContext (toString x86);
    armRoot = builtins.unsafeDiscardStringContext (toString arm);
  }
  ''
    mkdir bin
    cat > bin/nix <<'SH'
    #!${pkgs.runtimeShell}
    set -euo pipefail
    printf 'verify %s\n' "$4" >> "$CALLS"
    [[ "$4" != "''${FAIL_VERIFY:-}" ]]
    SH
    chmod +x bin/nix
    cat > bin/niks3 <<'SH'
    #!${pkgs.runtimeShell}
    set -euo pipefail
    if [[ "$1" == push ]]; then
      shift
      shift 2
      printf 'push %s\n' "$1" >> "$CALLS"
      [[ "$1" != "''${FAIL_ROOT:-}" ]]
    else
      printf 'pin %s %s\n' "$5" "$6" >> "$CALLS"
    fi
    SH
    chmod +x bin/niks3
    export PATH="$PWD/bin:$PATH" CALLS="$PWD/calls"
    export FAIL_ROOT="$armRoot"
    if bash "$effectScript"; then
      echo 'cache-retain hid a failed push' >&2
      exit 1
    fi
    python3 - <<'PY'
    import os
    from pathlib import Path
    x, a = os.environ["x86Root"], os.environ["armRoot"]
    assert Path(os.environ["CALLS"]).read_text().splitlines() == [
        f"push {x}", f"pin nix-homelab-main-x86_64-linux {x}", f"verify {x}",
        f"push {a}",
    ], "a failed push must prevent its pin and stop the effect"
    PY
    unset FAIL_ROOT
    bash "$effectScript"
    python3 - <<'PY'
    import os, tomllib
    from pathlib import Path
    x, a = os.environ["x86Root"], os.environ["armRoot"]
    assert Path(os.environ["CALLS"]).read_text().splitlines()[4:] == [
        f"push {x}", f"pin nix-homelab-main-x86_64-linux {x}", f"verify {x}",
        f"push {a}", f"pin nix-homelab-main-aarch64-linux {a}", f"verify {a}",
    ], "a repair run must publish, pin and verify both roots"
    policy = tomllib.loads(Path(os.environ["nixbotToml"]).read_text())
    assert policy["effects_on_pull_requests"] is False
    PY
    # A root the public endpoint does not serve must fail the effect even though
    # the push and the pin succeeded.
    : > "$CALLS"
    if FAIL_VERIFY="$x86Root" bash "$effectScript"; then
      echo 'cache-retain hid an unsubstitutable root' >&2
      exit 1
    fi
    touch "$out"
  ''
