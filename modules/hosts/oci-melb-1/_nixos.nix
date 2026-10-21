# Host-private NixOS composition for oci-melb-1: ./default.nix imports it as the
# record's deferred composition, and the underscore prefix keeps it (and every
# sibling fragment) out of discovery.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  hasHostSecrets = builtins.pathExists ../../../secrets/hosts/oci-melb-1/system.yaml;
in
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ./_disko-single-disk-split.nix
    ./_cockpit-auth.nix
  ];

  hardware.facter.reportPath = ./facter.json;

  networking = {
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

  boot.loader.grub.configurationLimit = 10;

  services.ingress = {
    role = "edge";
    secretFiles.host = ../../../secrets/applications/edge-ingress.yaml;
  };

  services = {
    paperless = {
      dataRoot = "/srv/data";
      secretFiles.host = ../../../secrets/services/paperless.yaml;
      secretFiles.oidc = ../../../secrets/hosts/oci-melb-1/oidc.yaml;
      oidc.enable = config.repo.web.catalog.paperless.access.oidc.enabled;
      # paperless-gpt is off pending re-evaluation: the stack's LLM/vision routing
      # and its OCR split have to be settled before it earns a generation again.
    };

    journald.settings.Journal = {
      SystemMaxUse = "300M";
      SystemKeepFree = "1G";
      MaxRetentionSec = "7day";
    };

    identity.oidc = {
      providerUrl = config.repo.web.catalog."kanidm-admin".publicUrl;
    };

    identity.hostAuth = {
      enable = true;
      sshIntegration = true;
      pamAllowedLoginGroups = [ "admins" ];
    };

    # The aspect owns the state path and the settings document; the host binds
    # only the host-scoped secret file.
    bifrost.secretFiles.host = ../../../secrets/services/bifrost.yaml;

    karakeep-pod = {
      oidc = {
        enable = config.repo.web.catalog.karakeep.access.oidc.enabled;
        providerName = "Kanidm";
        autoRedirect = true;
        disablePasswordAuth = true;
      };
      storage.s3.enable = true;
      secretFiles.host = ../../../secrets/services/karakeep-pod.yaml;
      secretFiles.oidc = ../../../secrets/hosts/oci-melb-1/oidc.yaml;
    };

    actual.secretFiles.oidc = ../../../secrets/hosts/oci-melb-1/oidc.yaml;

    memos.secretFiles.oidc = ../../../secrets/hosts/oci-melb-1/oidc.yaml;

    tududi.secretFiles = {
      host = ../../../secrets/services/tududi.yaml;
      oidc = ../../../secrets/hosts/oci-melb-1/oidc.yaml;
    };

    inbox-zero.secretFiles.host = ../../../secrets/services/inbox-zero.yaml;

    homarr = {
      secretFiles = {
        host = ../../../secrets/services/homarr.yaml;
        oidc = ../../../secrets/hosts/oci-melb-1/oidc.yaml;
      };
    };
    geopulse.secretFiles.host = ../../../secrets/services/geopulse.yaml;

    tailscale.debugMtu = 1200;

    hostRecovery = lib.mkIf hasHostSecrets {
      enable = true;
      secretFile = ../../../secrets/hosts/oci-melb-1/system.yaml;
      rescueUser = {
        name = "rescue";
      };
      reboot.onCalendar = "weekly";
    };

    # The backups aspect owns enablement, the secret path, and the bucket.
    state-backups.stagingRoot = "/srv/data/state-backups";

    niks3-cache = {
      # API token in the host scope; signing key and S3 credentials in the
      # service scope.
      secretFiles.apiToken = ../../../secrets/hosts/oci-melb-1/system.yaml;
      secretFiles.host = ../../../secrets/services/niks3.yaml;
    };

    postgres = {
      instances.postgres = {
        port = 5432;
        dataDir = "/srv/data/postgres";
      };

      # Consumers register themselves from their own modules.
    };

    # The cache server runs locally; the catalog endpoint is the colocated
    # loopback dial for it (host and port come from nix-fleet's canonical
    # niks3-write record, never restated here).
    niks3-publisher.serverUrl = config.repo.web.catalog."niks3-write".endpoint.url;

    notify = {
      secretFiles.host = ../../../secrets/services/notification-daemon.yaml;
      secretFiles.hostSystem = ../../../secrets/hosts/oci-melb-1/system.yaml;

      ntfy = {
        enable = true;
      };
    };
  };

  disko-root-extra = "20G";
  disko-data-size = "28G";
  disko-nix-size = "45G";

  environment.systemPackages = [
    pkgs.git
    pkgs.curl
    pkgs.wget
  ];

  sops.defaultSopsFile = ../../../secrets/common.yaml;

  programs.nix-ld = {
    enable = true;
    libraries = [
      pkgs.stdenv.cc.cc.lib
      pkgs.zlib
      pkgs.openssl
      pkgs.libuuid
      pkgs.xz
      pkgs.icu
    ];
  };

  # Container image storage belongs on the heavy-app partition: the 20G root
  # filled to 100% under /var/lib/containers and killed a pull mid-deploy.
  # Footgun: podman 5.8.6 refuses a relocated graphroot — its database
  # static-dir check still demands the default path, so a storage.conf
  # graphroot hard-fails every invocation with "database configuration
  # mismatch" (reproduced from a clean state). The bind mount keeps podman on
  # its default config while the bytes live on /srv/storage.
  fileSystems."/var/lib/containers" = {
    device = "/srv/storage/containers";
    fsType = "none";
    options = [ "bind" ];
  };

  system.stateVersion = "25.11";
}
