{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  hasHostSecrets = builtins.pathExists ../../../secrets/hosts/oci-melb-1/system.yaml;
  globals = import ../../../policy/globals.nix;
in
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    # Every deployed product, provider, and workload implementation arrives via
    # the placement aspects selected in the registry (D-053); this host keeps
    # only machine facts, explicit variants, and host-local fragments.
    ./disko-single-disk-split.nix
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

  fleet.foundation = {
    bootLoader = "grub";
    buildTmpfsSize = "8G";
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

  # Edge placement comes from the selected `edge` aspect; this host keeps only
  # its explicit origin role.
  applications."edge-ingress".role = "origin";

  services = {
    paperless = {
      dataRoot = "/srv/data";
      secretFiles.host = ../../../secrets/services/paperless.yaml;
      secretFiles.oidc = ../../../secrets/hosts/oci-melb-1/oidc.yaml;
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
      dataDir = "/srv/data/bifrost";
      configFile = globals.aiGateway.configFile;
      secretFiles.host = ../../../secrets/services/bifrost-gateway.yaml;
    };

    karakeep-pod = {
      oidc = {
        enable = config.repo.web.catalog.karakeep.access.oidc.enabled;
        clientId = config.services.identity.oidc.clients.karakeep.clientId;
        wellknownUrl = config.services.identity.oidc.clients.karakeep.wellknownUrl;
        providerName = "Kanidm";
        autoRedirect = true;
        disablePasswordAuth = true;
      };
      storage.s3.enable = true;
      secretFiles.host = ../../../secrets/services/karakeep-pod.yaml;
      secretFiles.oidc = ../../../secrets/hosts/oci-melb-1/oidc.yaml;
    };

    tailscale.debugMtu = 1200;

    hostRecovery = lib.mkIf hasHostSecrets {
      enable = true;
      secretFile = ../../../secrets/hosts/oci-melb-1/system.yaml;
      rescueUser = {
        name = "rescue";
      };
      reboot.onCalendar = "weekly";
    };

    # Real host variant only: the backups aspect owns enablement, the derived
    # secret path, and the derived bucket (OPS-3).
    state-backups.stagingRoot = "/srv/data/state-backups";

    niks3-cache = {
      hostSecretFile = ../../../secrets/hosts/oci-melb-1/system.yaml;
      secretFiles.host = ../../../secrets/services/niks3.yaml;
    };

    postgres-shared = {
      secretFile = ../../../secrets/services/postgres-shared.yaml;
      niks3.enable = true;
      paperless.enable = true;
      audiomuse.enable = true;
      litellm.enable = true;
    };

    # Cache server runs locally here; the conventional cache-upload default leaf
    # points peers at this host.
    niks3-auto-upload.serverUrl = "http://127.0.0.1:5751";

    notification-daemon = {
      secretFiles.host = ../../../secrets/services/notification-daemon.yaml;
      secretFiles.hostSystem = ../../../secrets/hosts/oci-melb-1/system.yaml;

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

  sops.defaultSopsFile = ../../../secrets/common.yaml;

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
