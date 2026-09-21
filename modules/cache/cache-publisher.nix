# Cache-publication aspect (bridge to nix-fleet's shared publisher).
#
# nix-fleet owns the closure-upload mechanism (`niks3-publisher`): the upstream
# post-build hook, the fail-closed serverUrl assertion and the API-token
# registration. This contributor supplies the fleet's conventions — the write
# endpoint from the niks3Write internal contract and the host-scoped push token,
# gated on the two-step sops bootstrap — so host records keep selecting
# `cache-publisher` and never learn the mechanism moved.
{ inputs, ... }:
{
  flake.modules.nixos.cache-publisher =
    { config, lib, ... }:
    let
      hostSystemSecret = ../../secrets/hosts + "/${config.networking.hostName}/system.yaml";
      hasHostSecrets = builtins.pathExists hostSystemSecret;
    in
    {
      imports = [ inputs.nix-fleet.modules.nixos.niks3-publisher ];

      services.niks3-publisher = lib.mkIf hasHostSecrets {
        # Composed from scheme/host/port rather than the contract's `url`, which
        # carries the derived FQDN: this client addresses the provider by its
        # short tailnet hostname, and the rendered value must stay byte-identical.
        serverUrl = lib.mkDefault (
          let
            niks3Write = config.repo.internal.niks3Write;
          in
          "${niks3Write.scheme}://${niks3Write.host}:${toString niks3Write.port}"
        );
        secretFiles.apiToken = hostSystemSecret;
      };
    };
}
