# Host-private composition; the underscore prefix keeps it out of discovery.
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
  ];

  hardware.facter.reportPath = ./facter.json;

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

  # One owner for the published wallpaper; rotation is a bucket copy, so it belongs where
  # the branding is curated rather than on every host that publishes assets.
  services.assets.wallpaper.enable = true;

  services = {
    paperless = {
      dataRoot = "/srv/data";
      secretFiles.host = ../../../secrets/services/paperless.yaml;
      secretFiles.oidc = ../../../secrets/hosts/oci-melb-1/oidc.yaml;
      oidc.enable = config.repo.web.catalog.paperless.access.oidc.enabled;
      # paperless-gpt is off pending re-evaluation: the stack's LLM/vision routing
      # and its OCR split have to be settled before it earns a generation again.
    };

    # The aspect owns the state path and the settings document; the host binds
    # only the host-scoped secret file.
    bifrost.secretFiles.host = ../../../secrets/services/bifrost.yaml;

    karakeep-pod = {
      oidc = {
        enable = config.repo.web.catalog.karakeep.access.oidc.enabled;
        autoRedirect = true;
        disablePasswordAuth = true;
        # Links the existing admin by email on the next OIDC login, so the provider swap keeps its role.
        allowDangerousEmailAccountLinking = true;
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
    geopulse.secretFiles.oidc = ../../../secrets/hosts/oci-melb-1/oidc.yaml;

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

    # The cache server runs here, so the catalog endpoint is the colocated loopback dial.
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

  # Image storage lives on /srv/storage: the 20G root filled and killed a pull, and podman
  # 5.8.6 refuses a relocated graphroot, hence a bind mount.
  fileSystems."/var/lib/containers" = {
    device = "/srv/storage/containers";
    fsType = "none";
    options = [ "bind" ];
  };

  system.stateVersion = "25.11";
}
