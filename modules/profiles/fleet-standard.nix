# Fleet-standard operator tooling shared by all managed hosts:
# nh garbage collection, nixbuild SSH access, niks3 cache upload +
# post-deploy registration, Beszel agent auth, and the per-host outbound
# dev-user SSH identity. Conventional secret paths derive from
# networking.hostName; hosts override only genuinely host-specific values.
{
  config,
  lib,
  ...
}:
let
  hostSystemSecret = ../../secrets/hosts + "/${config.networking.hostName}/system.yaml";
  hasHostSecrets = builtins.pathExists hostSystemSecret;
in
{
  imports = [
    ../shared/niks3-post-deploy.nix
    ../shared/nixbuild-ssh.nix
  ];

  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      dates = "daily";
      extraArgs = "--keep 3";
    };
  };

  services.niks3-auto-upload = lib.mkIf hasHostSecrets {
    enable = lib.mkDefault true;
    serverUrl = lib.mkDefault "http://oci-melb-1:5751";
    authTokenFile = "/run/secrets/niks3.api_token";
  };
  services.niks3-post-deploy.enable = true;
  fleet.nixbuild-ssh.enable = true;

  services.beszel-agent-auth = lib.mkIf hasHostSecrets {
    enable = true;
    secretFiles.host = hostSystemSecret;
  };

  fleet.hostIdentity.sshPrivateKeyFile = lib.mkIf hasHostSecrets hostSystemSecret;

  sops.secrets = lib.mkIf hasHostSecrets {
    # Cache-upload token; the niks3-cache server module re-defines this with
    # an owner when it is enabled (mkDefault yields to that definition).
    niks3_api_token = {
      sopsFile = lib.mkDefault hostSystemSecret;
      key = lib.mkDefault "niks3/api_token";
      path = lib.mkDefault "/run/secrets/niks3.api_token";
      mode = lib.mkDefault "0400";
    };
  };
}
