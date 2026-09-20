# Host-private NixOS composition for la-admin-1: ./default.nix imports it as the
# record's deferred composition, and the underscore prefix keeps it (and every
# sibling fragment) out of discovery.
{
  ...
}:
{
  imports = [
    ./_admin-runtime.nix
  ];

  hardware.facter.reportPath = ./facter.json;

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/44effe1c-64cf-4a8f-9e36-6e5378199f5a";
      fsType = "ext4";
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/1EDE-F013";
      fsType = "vfat";
      options = [
        "fmask=0077"
        "dmask=0077"
      ];
    };
  };

  fleet.foundation = {
    bootLoader = "systemd-boot";
    buildTmpfsSize = "50%";
  };

  # ens18 is the LA uplink; RA defaults kept, no bridge, no pinned DNS.
  fleet.networking.uplink.interface = "ens18";

  services = {
    admin.vaultwarden.secretFiles.host = ../../../secrets/applications/admin.yaml;

    admin.homepage.secretFiles.host = ../../../secrets/applications/admin.yaml;

    tailscale.debugMtu = 1200;

    notification-daemon = {
      secretFiles.host = ../../../secrets/services/notification-daemon.yaml;
      secretFiles.hostSystem = ../../../secrets/hosts/la-admin-1/system.yaml;
      ntfy = {
        enable = true;
        serverUrl = "http://127.0.0.1:2586";
      };
    };

    ntfy = {
      secretFiles.firebase = ../../../secrets/services/ntfy-firebase-key.json;
      auth = {
        # Publisher policy lives in the push-server aspect; this host supplies
        # only the encrypted auth file provisioned from it.
        secretFiles.auth = ../../../secrets/services/ntfy.yaml;
      };
    };

    identity.hostAuth = {
      enable = true;
      sshIntegration = true;
      pamAllowedLoginGroups = [ "admins" ];
    };

    hostRecovery = {
      enable = true;
      secretFile = ../../../secrets/hosts/la-admin-1/system.yaml;
      rescueUser.name = "rescue";
      reboot.onCalendar = "weekly";
    };

    admin.vaultwarden.smtpFrom = "admin@send.shrublab.xyz";
  };

  sops.defaultSopsFile = ../../../secrets/common.yaml;

  applications."edge-ingress" = {
    role = "edge";
    secretFiles.host = ../../../secrets/applications/edge-ingress.yaml;
  };

  system.stateVersion = "26.05";
}
