# Conventional cache-upload client defaults (raw private leaf, imported
# explicitly by each host record).
#
# Owns the niks3-auto-upload client defaults and the niks3 API-token sops
# registration that the legacy modules/profiles/fleet-standard.nix carried,
# without re-introducing the profile wrapper (design FND-6, responsibility
# table rows 9-10). The conventional host-scoped secret path is derived from
# networking.hostName exactly as fleet-standard derived it, so host records do
# not repeat the three-host registration.
#
# All values are mkDefault: the cache-server module (services/niks3.nix, only
# enabled on oci-melb-1) re-defines the token registration with an owner when
# it is enabled, and each host still overrides only genuinely host-specific
# values (oci-melb-1 points serverUrl at its loopback cache).
{ config, lib, ... }:
let
  hostSystemSecret = ../../../secrets/hosts + "/${config.networking.hostName}/system.yaml";
  hasHostSecrets = builtins.pathExists hostSystemSecret;
in
{
  services.niks3-auto-upload = lib.mkIf hasHostSecrets {
    enable = lib.mkDefault true;
    serverUrl = lib.mkDefault "http://oci-melb-1:5751";
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
}
