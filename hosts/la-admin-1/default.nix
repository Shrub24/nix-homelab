{
  lib,
  config,
  ...
}:
{
  imports = [
    ../../modules/profiles/base-server.nix
    ../../modules/profiles/fleet-standard.nix
    ../../modules/shared/web-policy.nix
    ../../modules/shared/kanidm-host-auth.nix
    ../../modules/applications/admin/default.nix
    ../../modules/services/notification-daemon
    ../../modules/services/ntfy.nix
    ../../modules/applications/edge-ingress.nix
    ../../modules/core/users.nix
    ./cockpit-auth.nix
    ./edge.nix
    ./quantum.nix
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
    "/build".options = lib.mkForce [
      "size=50%"
      "mode=0755"
    ];
  };

  # Preserve the existing UEFI systemd-boot installation. The shared base
  # forces GRUB removable-media plus canTouchEfiVariables = false; keep the
  # EFI-variable policy from base (do not touch NVRAM) and only switch the
  # loader implementation. systemd-boot updates the ESP with --no-variables.
  boot.loader = {
    grub.enable = lib.mkForce false;
    systemd-boot.enable = true;
  };

  networking.hostName = "la-admin-1";

  # Quantum deferred on LA for the initial cutover: force-disables the
  # ./quantum.nix import (which sets enable = true); OIDC wiring stays intact.
  services.admin.quantum.enable = lib.mkForce false;

  sops.defaultSopsFile = ../../secrets/common.yaml;
  sops.secrets = {
    tailscale_auth_key = {
      sopsFile = ../../secrets/hosts/la-admin-1/system.yaml;
      key = "tailscale/auth_key";
      path = "/run/secrets/tailscale.auth_key";
      mode = "0400";
    };
    cockpit_service_user_password_hash = {
      sopsFile = ../../secrets/hosts/la-admin-1/system.yaml;
      key = "cockpit/service_user/password_hash";
      path = "/run/secrets/cockpit.service_user.password_hash";
      mode = "0400";
    };
  };

  services.tailscale.authKeyFile = "/run/secrets/tailscale.auth_key";

  # Cap the LA-to-OCI Tailscale TUN MTU below the proven packet-size black hole.
  # Host-scoped workaround: no enrollment, identity, tag, firewall, route, or
  # experimental PMTUD change (see specs/network-access/spec.md).
  systemd.services.tailscaled.environment.TS_DEBUG_MTU = "1200";

  applications.admin = {
    enable = true;
    dataRoot = "/srv/data";
    secretFiles = {
      host = ../../secrets/applications/admin.yaml;
      identity = ../../secrets/identity/kanidm.yaml;
      identityProvisioning = ../../secrets/identity/provisioning.json;
      oidcClients = {
        termix = ../../secrets/hosts/la-admin-1/oidc.yaml;
        beszel = ../../secrets/hosts/la-admin-1/oidc.yaml;
        quantum = ../../secrets/hosts/la-admin-1/oidc.yaml;
        karakeep = ../../secrets/hosts/oci-melb-1/oidc.yaml;
        paperless = ../../secrets/hosts/oci-melb-1/oidc.yaml;
        cloudflare-access = ../../secrets/opentofu/oidc.yaml;
      };
    };
  };

  applications.edge-ingress.secretFiles.host = ../../secrets/applications/edge-ingress.yaml;

  services.notification-daemon = {
    enable = true;
    secretFiles.host = ../../secrets/services/notification-daemon.yaml;
    secretFiles.hostSystem = ../../secrets/hosts/la-admin-1/system.yaml;
    ntfy = {
      enable = true;
      serverUrl = "http://127.0.0.1:2586";
    };
  };

  services.ntfy = {
    enable = true;
    secretFiles.firebase = ../../secrets/services/ntfy-firebase-key.json;
    auth = {
      # ACL subjects are the bare-hostname ntfy publisher users that own each
      # host's publish token (declared in secrets/.templates/services/ntfy.yaml);
      # ntfy ACLs match user names.
      access = [
        "oci-melb-1:*:write-only"
        "la-admin-1:*:write-only"
        "home-forge:*:write-only"
      ];
      secretFiles.auth = ../../secrets/services/ntfy.yaml;
    };
  };

  services.identity.hostAuth = {
    enable = true;
    sshIntegration = true;
    pamAllowedLoginGroups = [ "admins" ];
  };

  services.hostRecovery = {
    enable = true;
    secretFile = ../../secrets/hosts/la-admin-1/system.yaml;
    rescueUser.name = "rescue";
    reboot.onCalendar = "weekly";
  };

  services.state-backups = {
    enable = true;
    secretFile = ../../secrets/hosts/la-admin-1/system.yaml;
    bucket = "shrublab-backup-la-admin-1";
  };

  services.admin.vaultwarden.smtpFrom = "admin@send.shrublab.xyz";

  system.stateVersion = "26.05";
}
