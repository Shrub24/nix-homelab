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
    ../../modules/profiles/fleet-standard.nix
    ../../modules/profiles/networking.nix
    ../../modules/shared/web-policy.nix
    ../../modules/shared/kanidm-host-auth.nix
    ../../modules/shared/identity-oidc.nix
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
    ./cockpit-auth.nix
  ];

  hardware.facter.reportPath = ./facter.json;

  networking = {
    hostName = "oci-melb-1";

    firewall.interfaces = {
      podman0.allowedTCPPorts = [
        5030
        4533
      ];
      podman2.allowedTCPPorts = [
        5432
        4533
      ];
      audiomuse0.allowedTCPPorts = [
        5432
      ];
    };
  };

  fleet.networking = {
    uplink.interface = "enp0s6";
    uplink.ipv6AcceptRA = false;
    dns.servers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
  };

  disko.devices.disk.main.device = "/dev/sda";

  # Music is disabled on this host by construction: the applications.music
  # module is not imported here, so no music service can wire up. The whole
  # music application (Navidrome, AudioMuse, Syncthing, ingest) moved to
  # home-forge as one wired composition. This host retains the shared
  # Postgres (audiomuse DB + backup) and the copied /srv/media tree stays as
  # rollback insurance until the cutover soaks.

  boot.loader.grub.configurationLimit = 10;

  systemd = {
    services = {
      podman-storage-prune = {
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

      # Cap the LA-to-OCI Tailscale TUN MTU below the proven packet-size black hole.
      # Host-scoped workaround: no enrollment, identity, tag, firewall, route, or
      # experimental PMTUD change (see specs/network-access/spec.md).
      tailscaled.environment.TS_DEBUG_MTU = "1200";
    };

    timers.podman-storage-prune = {
      description = "Periodic Podman storage prune";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
        RandomizedDelaySec = "1h";
        Persistent = true;
      };
    };
  };

  applications."edge-ingress" = {
    enable = true;
    role = "origin";
  };

  services = {
    paperless = {
      enable = true;
      dataRoot = "/srv/data";
      secretFiles.host = ../../secrets/services/paperless.yaml;
      secretFiles.oidc = ../../secrets/hosts/oci-melb-1/oidc.yaml;
      oidc = {
        enable = config.repo.web.catalog.paperless.access.oidc.enabled;
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

    journald.extraConfig = ''
      SystemMaxUse=300M
      SystemKeepFree=1G
      MaxRetentionSec=7day
    '';

    identity.oidc = {
      providerUrl = config.repo.web.catalog."kanidm-admin".publicUrl;
    };

    identity.hostAuth = {
      enable = true;
      sshIntegration = true;
      pamAllowedLoginGroups = [ "admins" ];
    };

    bifrost-gateway = {
      enable = true;
      dataDir = "/srv/data/bifrost";
      configFile = globals.aiGateway.configFile;
      secretFiles.host = ../../secrets/services/bifrost-gateway.yaml;
    };

    phoenix = {
      enable = true;
    };

    karakeep-pod = {
      enable = true;
      oidc = {
        enable = config.repo.web.catalog.karakeep.access.oidc.enabled;
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

    tailscale = lib.mkIf hasHostSecrets { authKeyFile = "/run/secrets/tailscale.auth_key"; };

    hostRecovery = lib.mkIf hasHostSecrets {
      enable = true;
      secretFile = ../../secrets/hosts/oci-melb-1/system.yaml;
      rescueUser = {
        name = "rescue";
      };
      reboot.onCalendar = "weekly";
    };

    beszel-agent-auth = {
      enable = true;
      secretFiles.host = ../../secrets/hosts/oci-melb-1/system.yaml;
    };

    state-backups = {
      enable = true;
      secretFile = ../../secrets/hosts/oci-melb-1/system.yaml;
      bucket = "shrublab-backup-oci-melb-1";
      stagingRoot = "/srv/data/state-backups";
    };

    niks3-cache = {
      enable = true;
      hostSecretFile = ../../secrets/hosts/oci-melb-1/system.yaml;
      secretFiles.host = ../../secrets/services/niks3.yaml;
    };

    postgres-shared = {
      enable = true;
      secretFile = ../../secrets/services/postgres-shared.yaml;
      niks3.enable = true;
      paperless.enable = true;
      audiomuse.enable = true;
      litellm.enable = true;
    };

    # Cache server runs locally here; fleet-standard defaults point peers at it.
    niks3-auto-upload.serverUrl = "http://127.0.0.1:5751";

    notification-daemon = {
      enable = true;
      secretFiles.host = ../../secrets/services/notification-daemon.yaml;
      secretFiles.hostSystem = ../../secrets/hosts/oci-melb-1/system.yaml;

      ntfy = {
        enable = true;
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

  sops.secrets = lib.optionalAttrs hasHostSecrets {
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
  };

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

  system.stateVersion = "25.11";
}
