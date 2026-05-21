{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  hasHostSecrets = builtins.pathExists ../../secrets/hosts/oci-melb-1/system.yaml;
  globals = import ../../policy/globals.nix;
in
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ../../modules/profiles/base-server.nix
    ../../modules/shared/web-policy.nix
    ../../modules/shared/kanidm-host-auth.nix
    ../../modules/shared/identity-oidc.nix
    ../../modules/applications/music
    ../../modules/applications/edge-ingress.nix
    ../../modules/providers/oci/default.nix
    ../../modules/storage/disko-single-disk-split.nix
    ../../modules/core/users.nix
    ../../modules/services/admin/cockpit.nix
    ../../modules/services/notification-daemon
    ../../modules/services/bifrost-gateway.nix
    ../../modules/services/karakeep.nix
    ../../modules/services/niks3.nix
    ../../modules/services/postgres-shared.nix
    ../../modules/shared/niks3-post-deploy.nix
    ../../modules/shared/nixbuild-ssh.nix
    ./cockpit-auth.nix
  ]
  ++ lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix;

  networking.hostName = "oci-melb-1";
  services.resolved.enable = true;
  networking.nameservers = [
    "1.1.1.1"
    "8.8.8.8"
  ];
  networking.firewall.interfaces.podman0.allowedTCPPorts = [
    5030
    4533
  ];

  disko.devices.disk.main.device = "/dev/sda";
  applications.music.enable = true;
  applications.music.dataRoot = "/srv/data";
  applications.music.mediaRoot = "/srv/media";
  applications.music.secretFiles.host = ../../secrets/applications/music.yaml;

  boot.loader.grub.configurationLimit = 10;

  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 14d";
  };

  services.journald.extraConfig = ''
    SystemMaxUse=300M
    SystemKeepFree=1G
    MaxRetentionSec=7day
  '';

  systemd.services.podman-storage-prune = {
    description = "Prune unused Podman storage artifacts";
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
    script = ''
      set -euo pipefail
      podman system prune --all --force --volumes
    '';
  };

  systemd.timers.podman-storage-prune = {
    description = "Periodic Podman storage prune";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
  };

  applications."edge-ingress" = {
    enable = true;
    role = "origin";
  };

  services.identity.oidc = {
    providerUrl = config.repo.web.hosts.do-admin-1.services."kanidm-admin".publicUrl;
  };

  services.identity.hostAuth = {
    enable = true;
    sshIntegration = true;
    pamAllowedLoginGroups = [ "shrublab-admins" ];
  };

  services.bifrost-gateway = {
    enable = true;
    dataDir = "/srv/data/bifrost";
    configFile = globals.aiGateway.configFile;
    secretFiles.host = ../../secrets/services/bifrost-gateway.yaml;
  };

  services.karakeep-pod = {
    enable = true;
    oidc = {
      enable = config.repo.web.hosts.do-admin-1.services.karakeep.access.oidc.enabled;
      clientId = config.services.identity.oidc.clients.karakeep.clientId;
      wellknownUrl = config.services.identity.oidc.clients.karakeep.wellknownUrl;
      providerName = "Kanidm";
      autoRedirect = true;
      disablePasswordAuth = true;
    };
    storage.s3.enable = true;
    secretFiles.host = ../../secrets/services/karakeep-pod.yaml;
    secretFiles.oidc = ../../secrets/hosts/oci-melb-1/oidc.yaml;
  };

  disko-root-extra = "20G";
  disko-data-size = "28G";
  disko-nix-size = "45G";

  environment.systemPackages = with pkgs; [
    git
    curl
    wget
  ];

  sops.defaultSopsFile = ../../secrets/common.yaml;

  sops.secrets = (
    lib.optionalAttrs hasHostSecrets {
      tailscale_auth_key = {
        sopsFile = ../../secrets/hosts/oci-melb-1/system.yaml;
        key = "tailscale/auth_key";
        path = "/run/secrets/tailscale.auth_key";
        mode = "0400";
      };
      cockpit_service_user_password_hash = {
        sopsFile = ../../secrets/hosts/oci-melb-1/system.yaml;
        key = "cockpit/service_user/password_hash";
        path = "/run/secrets/cockpit.service_user.password_hash";
        owner = "root";
        group = "root";
        mode = "0400";
      };
    }
  );

  services.tailscale = lib.mkIf hasHostSecrets { authKeyFile = "/run/secrets/tailscale.auth_key"; };

  services.hostRecovery = lib.mkIf hasHostSecrets {
    enable = true;
    secretFile = ../../secrets/hosts/oci-melb-1/system.yaml;
    rescueUser = {
      name = "rescue";
    };
    reboot.onCalendar = "weekly";
  };

  services.beszel-agent-auth = {
    enable = true;
    secretFiles.host = ../../secrets/hosts/oci-melb-1/system.yaml;
  };

  services.state-backups = {
    enable = true;
    secretFile = ../../secrets/hosts/oci-melb-1/system.yaml;
    bucket = "shrublab-backup-oci-melb-1";
    stagingRoot = "/srv/data/state-backups";
  };

  services.niks3-cache = {
    enable = true;
    hostSecretFile = ../../secrets/hosts/oci-melb-1/system.yaml;
    secretFiles.host = ../../secrets/services/niks3.yaml;
  };

  services.postgres-shared = {
    enable = true;
    niks3.enable = true;
  };

  services.niks3-auto-upload = {
    enable = true;
    serverUrl = "http://127.0.0.1:5751";
    authTokenFile = "/run/secrets/niks3.api_token";
  };
  services.niks3-post-deploy.enable = true;

  fleet.nixbuild-ssh.enable = true;

  fleet.hostIdentity.sshPrivateKeyFile = ../../secrets/hosts/oci-melb-1/system.yaml;

  services.tagr.backup.exportFile = "/srv/data/state-backups/tagr/tagr.sqlite3";

  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      openssl
      libuuid
      xz
      icu
    ];
  };

  services.notification-daemon = {
    enable = true;
    secretFiles.host = ../../secrets/services/notification-daemon.yaml;

    ntfy = {
      enable = true;
      serverUrl = "https://ntfy.shrublab.xyz";
    };
  };

  system.stateVersion = "25.11";
}
