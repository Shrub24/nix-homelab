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
    ../../modules/services/paperless
    ../../modules/applications/edge-ingress.nix
    ../../modules/providers/oci/default.nix
    ../../modules/storage/disko-single-disk-split.nix
    ../../modules/core/users.nix
    ../../modules/services/admin/cockpit.nix
    ../../modules/services/notification-daemon
    ../../modules/services/bifrost-gateway.nix
    ../../modules/services/phoenix.nix
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
  networking.firewall.interfaces.podman2.allowedTCPPorts = [
    5432
    4533
  ];
  networking.firewall.interfaces.audiomuse0.allowedTCPPorts = [
    5432
  ];

  disko.devices.disk.main.device = "/dev/sda";
  applications.music.enable = true;
  applications.music.audiomuse.enable = true;
  applications.music.dataRoot = "/srv/data";
  applications.music.mediaRoot = "/srv/media";
  applications.music.secretFiles.host = ../../secrets/applications/music.yaml;

  services.paperless = {
    enable = true;
    dataRoot = "/srv/data";
    secretFiles.host = ../../secrets/services/paperless.yaml;
    secretFiles.oidc = ../../secrets/hosts/oci-melb-1/oidc.yaml;
    oidc = {
      enable = config.repo.web.hosts.do-admin-1.services.paperless.access.oidc.enabled;
      clientId = config.services.identity.oidc.clients.paperless.clientId;
      wellknownUrl = config.services.identity.oidc.clients.paperless.wellknownUrl;
    };
    paperless-gpt = {
      docling.enable = false;
      instances.llm = {
        enable = true;
        environment.LLM_MODEL = globals.aiGateway.aliases.text;
        environment.VISION_LLM_MODEL = globals.aiGateway.aliases.image;
      };
      instances.docling.enable = false;
    };
  };

  boot.loader.grub.configurationLimit = 10;

  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      dates = "daily";
      extraArgs = "--keep 3";
    };
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
    pamAllowedLoginGroups = [ "admins" ];
  };

  services.bifrost-gateway = {
    enable = true;
    dataDir = "/srv/data/bifrost";
    configFile = globals.aiGateway.configFile;
    secretFiles.host = ../../secrets/services/bifrost-gateway.yaml;
  };

  services.phoenix = {
    enable = true;
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
    secretFile = ../../secrets/services/postgres-shared.yaml;
    niks3.enable = true;
    paperless.enable = true;
    audiomuse.enable = true;
    litellm.enable = true;
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
    secretFiles.hostSystem = ../../secrets/hosts/oci-melb-1/system.yaml;

    ntfy = {
      enable = true;
      serverUrl = "https://ntfy.shrublab.xyz";
    };

    monitor = {
      enable = true;
      services = [
        "beets-inbox"
        "beets-reconcile"
        "beets-duplicates"
        "podman-storage-prune"
        "nh-clean-all"
        "beszel-agent"
      ];
    };
  };

  system.stateVersion = "25.11";
}
