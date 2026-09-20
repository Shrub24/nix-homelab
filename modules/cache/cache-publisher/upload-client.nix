# Cache-upload client contributor of the cache-publisher aspect (OPSPLIT-1):
# the niks3-auto-upload client defaults and the niks3 API-token sops
# registration, owning the conventional host-scoped secret path derived from
# networking.hostName. It contributes to the same
# `flake.modules.nixos.cache-publisher` publication as ../cache-publisher.nix.
{
  flake.modules.nixos.cache-publisher =
    { config, lib, ... }:
    let
      hostSystemSecret = ../../../secrets/hosts + "/${config.networking.hostName}/system.yaml";
      hasHostSecrets = builtins.pathExists hostSystemSecret;

      # Private write endpoint resolved through the internal transport contract
      # (stage 8 task 4.2, HIC-4) instead of a provider literal. The `scheme`/
      # `host`/`port` fields are used rather than `url`: `url` carries the derived
      # FQDN, while this client has always addressed the provider by its short
      # tailnet hostname, so composing from host+port keeps the rendered value
      # byte-identical. Still mkDefault, so an explicit host override (oci-melb-1
      # points at its loopback cache) continues to win.
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
