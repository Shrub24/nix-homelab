# Bridge to nix-fleet's niks3 publisher: it owns the closure upload, this supplies the
# write endpoint and the host-scoped push token.
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
        # One declaration for both sides: the provider listens on `endpoint.port`, this
        # client dials `endpoint.url`.
        serverUrl = lib.mkDefault config.repo.web.catalog."niks3-write".endpoint.url;
        secretFiles.apiToken = hostSystemSecret;
      };
    };
}
