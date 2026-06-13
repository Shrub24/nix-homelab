{
  lib,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ../../modules/profiles/base-server.nix
    ../../modules/shared/web-policy.nix
    ../../modules/shared/kanidm-host-auth.nix
    ../../modules/applications/admin/default.nix
    ../../modules/services/notification-daemon
    ../../modules/services/ntfy.nix
    ../../modules/applications/edge-ingress.nix
    ../../modules/providers/digitalocean/default.nix
    ../../modules/storage/disko-single-disk.nix
    ../../modules/core/users.nix
    ../../modules/shared/niks3-post-deploy.nix
    ../../modules/shared/nixbuild-ssh.nix
    ./quantum.nix
    ./cockpit-auth.nix
    ./edge.nix
    ./networking.nix
  ]
  ++ lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix;

  networking.hostName = "do-admin-1";
  sops.defaultSopsFile = ../../secrets/common.yaml;
  sops.secrets = {
    tailscale_auth_key = {
      sopsFile = ../../secrets/hosts/do-admin-1/system.yaml;
      key = "tailscale/auth_key";
      path = "/run/secrets/tailscale.auth_key";
      mode = "0400";
    };
    cockpit_service_user_password_hash = {
      sopsFile = ../../secrets/hosts/do-admin-1/system.yaml;
      key = "cockpit/service_user/password_hash";
      path = "/run/secrets/cockpit.service_user.password_hash";
      mode = "0400";
    };
    niks3_api_token = {
      sopsFile = ../../secrets/hosts/do-admin-1/system.yaml;
      key = "niks3/api_token";
      path = "/run/secrets/niks3.api_token";
      mode = "0400";
    };
  };
  services.tailscale.authKeyFile = "/run/secrets/tailscale.auth_key";
  disko.devices.disk.main.device = "/dev/vda";
  disko-root-extra = "100%";
  applications.admin.enable = true;
  applications.admin.dataRoot = "/srv/data";
  services.notification-daemon = {
    enable = true;
    secretFiles.host = ../../secrets/services/notification-daemon.yaml;
    secretFiles.hostSystem = ../../secrets/hosts/do-admin-1/system.yaml;

    ntfy = {
      enable = true;
      serverUrl = "http://127.0.0.1:2586";
    };
  };

  services.ntfy = {
    enable = true;
    secretFiles.firebase = ../../secrets/services/ntfy-firebase-key.json;
    auth = {
      access = [
        "notify-oci-melb-1:*:write-only"
        "notify-do-admin-1:*:write-only"
      ];
      secretFiles.auth = ../../secrets/services/ntfy.yaml;
    };
  };

  applications.admin.secretFiles.host = ../../secrets/applications/admin.yaml;
  applications.admin.secretFiles.identity =
    if builtins.pathExists ../../secrets/identity/kanidm.yaml then
      ../../secrets/identity/kanidm.yaml
    else
      null;
  applications.admin.secretFiles.identityProvisioning =
    if builtins.pathExists ../../secrets/identity/provisioning.json then
      ../../secrets/identity/provisioning.json
    else
      null;
  applications.admin.secretFiles.oidcClients = {
    termix = ../../secrets/hosts/do-admin-1/oidc.yaml;
    beszel = ../../secrets/hosts/do-admin-1/oidc.yaml;
    quantum = ../../secrets/hosts/do-admin-1/oidc.yaml;
    karakeep = ../../secrets/hosts/oci-melb-1/oidc.yaml;
    paperless = ../../secrets/hosts/oci-melb-1/oidc.yaml;
    cloudflare-access = ../../secrets/opentofu/oidc.yaml;
  };
  applications.edge-ingress.enable = true;
  applications.edge-ingress.role = "edge";
  applications.edge-ingress.primaryDomain = "shrublab.xyz";
  applications.edge-ingress.acmeEmail = lib.mkDefault "admin@send.shrublab.xyz";
  applications.edge-ingress.secretFiles.host = ../../secrets/applications/edge-ingress.yaml;
  services.identity.hostAuth = {
    enable = true;
    sshIntegration = true;
    pamAllowedLoginGroups = [ "admins" ];
  };
  services.hostRecovery = {
    enable = true;
    secretFile = ../../secrets/hosts/do-admin-1/system.yaml;
    rescueUser = {
      name = "rescue";
    };
    reboot.onCalendar = "weekly";
  };
  services.beszel-agent-auth = {
    enable = true;
    secretFiles.host = ../../secrets/hosts/do-admin-1/system.yaml;
  };
  services.state-backups = {
    enable = true;
    secretFile = ../../secrets/hosts/do-admin-1/system.yaml;
    bucket = "shrublab-backup-do-admin-1";
  };
  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      dates = "daily";
      extraArgs = "--keep 3";
    };
  };

  services.niks3-auto-upload = {
    enable = true;
    serverUrl = "http://oci-melb-1:5751";
    authTokenFile = "/run/secrets/niks3.api_token";
  };
  services.niks3-post-deploy.enable = true;

  fleet.nixbuild-ssh.enable = true;

  fleet.hostIdentity.sshPrivateKeyFile = ../../secrets/hosts/do-admin-1/system.yaml;

  services.admin.vaultwarden.smtpFrom = "admin@send.shrublab.xyz";

  system.stateVersion = "25.11";
}
