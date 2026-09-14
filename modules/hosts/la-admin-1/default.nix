{
  ...
}:
{
  imports = [
    # Every deployed product and platform capability arrives via the placement
    # aspects selected in the registry (D-053); this host keeps only machine
    # facts, explicit variants, and host-local fragments.
    ./cockpit-auth.nix
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

  networking.hostName = "la-admin-1";

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
        # ACL subjects are the bare-hostname ntfy publisher users that own each
        # host's publish token (declared in secrets/.templates/services/ntfy.yaml);
        # ntfy ACLs match user names.
        access = [
          "oci-melb-1:*:write-only"
          "la-admin-1:*:write-only"
          "home-forge:*:write-only"
        ];
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
