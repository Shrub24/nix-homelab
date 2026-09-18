# Host-private NixOS composition for la-admin-1 (Stage 8 HIC-2, task 2.2). The
# canonical typed record lives in ./default.nix and imports this fragment as its
# deferred composition; underscore-named siblings keep every host-private
# fragment out of discovery.
{
  ...
}:
{
  imports = [
    # Every deployed product and platform capability arrives via the placement
    # aspects selected in this host's canonical record (Stage 8 HIC-1/HIC-2);
    # this fragment keeps only machine facts, explicit variants, and host-local
    # fragments.
    ./_cockpit-auth.nix
    # Host-local admin runtime remainder (decouple-identity-admin-capabilities 3.3).
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

  # Base aspect host facts (FND-2): systemd-boot loader and 50% /build tmpfs.
  fleet.foundation = {
    bootLoader = "systemd-boot";
    buildTmpfsSize = "50%";
  };

  # Networking aspect fact: ens18 is the LA uplink (design D4/D8). RA defaults
  # kept, no bridge, no pinned DNS today.
  fleet.networking.uplink.interface = "ens18";

  services = {
    # Termix placement comes from the selected `termix` aspect; the host keeps
    # only its host-scoped OIDC client secret source.
    admin.termix.secretFiles.oidc = ../../../secrets/hosts/la-admin-1/oidc.yaml;

    # Vaultwarden placement comes from the selected `vaultwarden` aspect; the
    # host keeps only its host-scoped secret source
    # (decouple-identity-admin-capabilities 3.1).
    admin.vaultwarden.secretFiles.host = ../../../secrets/applications/admin.yaml;

    # Homepage placement comes from the selected `homepage` aspect; the host
    # keeps only its host-scoped secret source
    # (decouple-identity-admin-capabilities 3.2).
    admin.homepage.secretFiles.host = ../../../secrets/applications/admin.yaml;

    # Tailscale foundation aspect owns auth-key registration and MTU rendering
    # (FND-4); the host only declares its host-scoped variant.
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
        # Publisher policy (who may publish, and with which permission) lives in
        # the push-server aspect; this host only supplies the encrypted auth
        # file that provisions the matching users and tokens.
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

  # Edge placement comes from the selected `edge` aspect; this host keeps only
  # its explicit edge role and application-scoped secret binding.
  applications."edge-ingress" = {
    role = "edge";
    secretFiles.host = ../../../secrets/applications/edge-ingress.yaml;
  };

  system.stateVersion = "26.05";
}
