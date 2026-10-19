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

  # Secret activation is the fleet policy now, supplied by the
  # `sops-systemd-activation` aspect, so this host sets nothing here. The
  # activation-script path it replaces is the mechanism NixOS 26.11 removes, and
  # it is the one that queues restarts through
  # `/run/nixos/activation-restart-list`; the unit path orders against
  # `sysinit.target` and `sysinit-reactivation.target`. `neededForUsers` secrets
  # are unaffected: sops-nix keys that split on `systemd.sysusers`/`userborn`,
  # which this fleet does not use, so the rescue-password secret keeps its
  # activation-script install ahead of user creation (`users.deps`).

  services = {
    admin.vaultwarden.secretFiles.host = ../../../secrets/applications/admin.yaml;

    admin.homepage.secretFiles.host = ../../../secrets/applications/admin.yaml;

    tailscale.debugMtu = 1200;

    notify = {
      secretFiles.host = ../../../secrets/services/notification-daemon.yaml;
      secretFiles.hostSystem = ../../../secrets/hosts/la-admin-1/system.yaml;
      ntfy = {
        # No server URL override: the catalog endpoint already resolves loopback
        # here, because this host serves ntfy.
        enable = true;
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

  services.ingress = {
    role = "origin";
  };

  system.stateVersion = "26.05";
}
