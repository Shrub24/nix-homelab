# Cache-publication aspect (bridge to nix-fleet's shared publisher).
#
# nix-fleet owns the closure-upload mechanism (`niks3-publisher`): the upstream
# post-build hook, the fail-closed serverUrl assertion and the API-token
# registration. This contributor supplies the fleet's conventions — the write
# endpoint from the service policy's private projection and the host-scoped push
# token, gated on the two-step sops bootstrap — so host records keep selecting
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
        # The published private endpoint is the single source for both sides:
        # the provider listens on `endpoint.port`, this client dials
        # `endpoint.url`.
        serverUrl = lib.mkDefault config.repo.web.catalog."niks3-write".endpoint.url;
        secretFiles.apiToken = hostSystemSecret;
      };
    };
}
