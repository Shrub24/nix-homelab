# Cache-upload client contributor of the cache-publisher aspect: the
# niks3-auto-upload client defaults and the niks3 API-token sops registration,
# owning the host-scoped secret path derived from networking.hostName.
{
  flake.modules.nixos.cache-publisher =
    { config, lib, ... }:
    let
      hostSystemSecret = ../../../secrets/hosts + "/${config.networking.hostName}/system.yaml";
      hasHostSecrets = builtins.pathExists hostSystemSecret;

      # Composed from scheme/host/port rather than `url`, which carries the
      # derived FQDN: this client addresses the provider by its short tailnet
      # hostname, and the rendered value must stay byte-identical.
      niks3Write = config.repo.internal.niks3Write;
    in
    {
      services.niks3-auto-upload = lib.mkIf hasHostSecrets {
        enable = lib.mkDefault true;
        serverUrl = lib.mkDefault "${niks3Write.scheme}://${niks3Write.host}:${toString niks3Write.port}";
        authTokenFile = "/run/secrets/niks3.api_token";
      };

      sops.secrets = lib.mkIf hasHostSecrets {
        niks3_api_token = {
          sopsFile = lib.mkDefault hostSystemSecret;
          key = lib.mkDefault "niks3/api_token";
          path = lib.mkDefault "/run/secrets/niks3.api_token";
          mode = lib.mkDefault "0400";
        };
      };
    };
}
