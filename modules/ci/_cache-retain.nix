# The main-push retention effect: push each system's root, move its rolling pin,
# then prove the root is substitutable. A value-imported helper of effects.nix.
{
  config,
  lib,
  pkgs,
  effects,
}:
primaryRepo:
let
  cacheUrl = config.flake.nixosConfigurations.oci-melb-1.config.services.niks3-cache.cacheUrl;
  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
  roots = lib.genAttrs systems (system: config.flake.packages.${system}.cache-root);
  writeEndpoint =
    config.flake.nixosConfigurations.home-forge.config.repo.web.catalog."niks3-write".endpoint.url;
  # A pin refuses a root the cache does not hold, so each root is pushed first.
  # Reconciliation runs on an unchanged root too: a missed streaming upload is
  # repaired by rerunning, never by a changed-only guard.
  retain = system: ''
    niks3 push "''${auth[@]}" ${roots.${system}}
    niks3 pins create "''${auth[@]}" nix-homelab-main-${system} ${roots.${system}}
    nix path-info --store ${lib.escapeShellArg cacheUrl} ${roots.${system}} >/dev/null \
      || { echo "cache-retain: ${system} root is not substitutable from ${cacheUrl}" >&2; exit 1; }
  '';
  script = ''
    set -euo pipefail
    export NIKS3_SERVER_URL=${lib.escapeShellArg writeEndpoint}
    auth=(--auth-token-script "nixbot-id-token ${cacheUrl} --json")
    ${lib.concatMapStringsSep "\n" retain systems}
  '';
in
lib.optionalAttrs ((primaryRepo.branch or null) == "main" && (primaryRepo.tag or null) == null) {
  cache-retain = effects.mkEffect {
    name = "cache-retain";
    idTokenAudiences = [ cacheUrl ];
    secretsMap = { };
    lock = "cache";
    # niks3 invokes the Nix CLI to query the closure through the runner's daemon proxy.
    inputs = [
      config.flake.packages.${config.nixos.hosts.home-forge.system}.niks3
      config.flake.nixosConfigurations.home-forge.config.nix.package
    ]
    ++ lib.attrValues roots;
    effectScript = script;
  };
}
