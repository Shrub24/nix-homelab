# Base foundation aspect (private leaf; the only public composition unit is
# flake.modules.nixos.base in modules/flake/aspects.nix).
#
# Owns base OS policy, users, Nix/`nh` tuning, the outbound dev SSH identity
# convention, host recovery, and the two typed machine facts that replaced the
# legacy per-host boot and `/build` override conflicts (design FND-2):
#
#   fleet.foundation.bootLoader = "grub" | "systemd-boot";  # required
#   fleet.foundation.buildTmpfsSize = "8G" | "50%";          # required str
#
# The loader implementation and the `/build` tmpfs size are rendered from
# those facts, so hosts declare facts instead of fighting shared defaults with
# mkForce (design DS-4 / dendritic-stage-2 FND-2).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Conventional host-scoped SOPS scope. Every per-host secret path derives
  # from networking.hostName (specs/secrets-management); an absent host system
  # scope keeps the two-step sops bootstrap working.
  hostSystemSecret = ../../../secrets/hosts + "/${config.networking.hostName}/system.yaml";
  hasHostSecrets = builtins.pathExists hostSystemSecret;

  globals = import ../../../policy/globals.nix;
  nixPolicy = globals.services.nix or { };

  foundation = config.fleet.foundation;
  hostIdentity = config.fleet.hostIdentity;

  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFBqFsxbrn6SVOHXi4+LS5olKxEW8JlZ5V+irA18/586 saurabhj@arch"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMrzW7nXTeKqejlnIYmccciDJ4/PfjV6ek4Wvo7v86/a termix"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBsHnolkmLVudDN3HKQ/Q4Xw2ZqDVjax177hbi15jqRW la-admin-1-dev@shrublab"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINRh71N504a6X1OkZ6XxhJrllHiEEWC/4o5s3+RtPuI8 home-forge-dev@shrublab"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBeKFT2RvMo1WvF+f8Q6W8cU2wn31aCG1k9onz6Y+fqz root@arch"
  ];
in
{
  # Host recovery is a private leaf owned by the base aspect (FND-6): it is
  # part of break-glass base policy, not an independently selected capability.
  imports = [ ../../shared/host-recovery.nix ];

  options = {
    fleet.foundation = {
      bootLoader = lib.mkOption {
        type = lib.types.enum [
          "grub"
          "systemd-boot"
        ];
        description = ''
          Boot loader implementation rendered by the base aspect from this
          typed host fact. "grub" renders the shared GRUB removable-media EFI
          settings; "systemd-boot" renders a systemd-boot ESP install. The
          common canTouchEfiVariables = false policy applies either way.
        '';
      };

      buildTmpfsSize = lib.mkOption {
        type = lib.types.str;
        description = ''
          Size rendered for the /build tmpfs mount (e.g. "8G" or "50%").
          Required per host so shared base policy never needs a host-local
          override conflict to differ from the common default.
        '';
      };
    };

    # Outbound dev SSH identity contract (FND-6): the option and its
    # conditional template/secret rendering are preserved from the legacy
    # base-server profile; the conventional host-scoped default is derived
    # here instead of in each host record.
    fleet.hostIdentity.sshPrivateKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Host-scoped SOPS file containing the dev user SSH identity private key.";
    };
  };

  config = {
    # --- Base OS policy (was modules/core/base.nix) -------------------------
    # Shared Nix defaults (core/base) plus the substituter/tuning policy that
    # base-server previously contributed through a separate module merge.
    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      trusted-users = [
        "root"
        "dev"
      ];
      substituters = lib.mkAfter (nixPolicy.substituters or [ ]);
      trusted-substituters = lib.mkAfter (nixPolicy.trustedSubstituters or [ ]);
      trusted-public-keys = lib.mkAfter (nixPolicy.trustedPublicKeys or [ ]);
      max-jobs = 2;
      cores = 0;
      max-substitution-jobs = 8;
      http-connections = 64;
      download-buffer-size = 268435456;
    };

    time.timeZone = "UTC";

    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "prohibit-password";
      };
    };

    security.sudo.wheelNeedsPassword = false;

    # --- Boot loader and /build rendered from typed facts -------------------
    boot.loader = lib.mkMerge [
      # Common EFI policy: do not touch NVRAM on fleet hosts.
      { efi.canTouchEfiVariables = false; }
      (lib.mkIf (foundation.bootLoader == "grub") {
        grub = {
          enable = true;
          efiSupport = true;
          efiInstallAsRemovable = true;
        };
      })
      (lib.mkIf (foundation.bootLoader == "systemd-boot") {
        grub.enable = false;
        systemd-boot.enable = true;
      })
    ];

    fileSystems."/build" = {
      fsType = "tmpfs";
      options = [
        "size=${foundation.buildTmpfsSize}"
        "mode=0755"
      ];
    };

    # --- Users (was modules/core/users.nix) ---------------------------------
    users = {
      mutableUsers = false;

      users.dev = {
        isNormalUser = true;
        description = "Dev User";
        extraGroups = [
          "wheel"
        ];
        shell = pkgs.zsh;
        openssh.authorizedKeys.keys = sshKeys;
      };

      users.root = {
        shell = pkgs.bashInteractive;
        openssh.authorizedKeys.keys = sshKeys;
      };
    };

    systemd.tmpfiles.settings."user-homes" = {
      "/home/dev/.config".d = {
        user = "dev";
        group = "users";
        mode = "0755";
      };
      "/home/dev/.cache".d = {
        user = "dev";
        group = "users";
        mode = "0755";
      };
      "/home/dev/.local".d = {
        user = "dev";
        group = "users";
        mode = "0755";
      };
      "/home/dev/.local/share".d = {
        user = "dev";
        group = "users";
        mode = "0755";
      };
      "/home/dev/.local/state".d = {
        user = "dev";
        group = "users";
        mode = "0755";
      };
    };

    # --- Shared host policy (was modules/profiles/base-server.nix) -----------
    networking.firewall.allowedTCPPorts = lib.mkDefault [ 22 ];
    networking.firewall.trustedInterfaces = lib.mkAfter [ "tailscale0" ];

    boot.kernelModules = [ "tcp_bbr" ];
    boot.kernel.sysctl = {
      "net.ipv4.tcp_congestion_control" = "bbr";
      "net.core.rmem_max" = 16777216;
      "net.core.wmem_max" = 16777216;
      "net.ipv4.tcp_rmem" = "4096 131072 16777216";
      "net.ipv4.tcp_wmem" = "4096 65536 16777216";
      "net.core.netdev_max_backlog" = 16384;
    };

    # Use mq-deadline scheduler for better I/O fairness on shared block devices
    services.udev.extraRules = ''
      ACTION=="add|change", KERNEL=="sd[a-z]|vd[a-z]", ATTR{queue/scheduler}="mq-deadline"
    '';

    # --- Operator tooling (was modules/profiles/fleet-standard.nix) ----------
    programs.nh = {
      enable = true;
      clean = {
        enable = true;
        dates = "daily";
        extraArgs = "--keep 3";
      };
    };

    # --- Outbound dev SSH identity (FND-6) -----------------------------------
    # Conventional default: the host system scope, when it exists. The
    # conditional option/template contract below is unchanged from the legacy
    # base-server profile.
    fleet.hostIdentity.sshPrivateKeyFile = lib.mkIf hasHostSecrets hostSystemSecret;

    programs.ssh.extraConfig = lib.mkIf (hostIdentity.sshPrivateKeyFile != null) ''
      Host *
      IdentityFile /run/secrets/host.ssh_identity
      IdentitiesOnly yes
    '';

    sops.templates."host-ssh-identity" = lib.mkIf (hostIdentity.sshPrivateKeyFile != null) {
      content = ''
        ${config.sops.placeholder.host_ssh_identity_raw}
      '';
      path = "/run/secrets/host.ssh_identity";
      mode = "0400";
    };
    sops.secrets = lib.mkIf (hostIdentity.sshPrivateKeyFile != null) {
      host_ssh_identity_raw = {
        sopsFile = hostIdentity.sshPrivateKeyFile;
        key = "identity/ssh_private_key";
        mode = "0400";
      };
    };
  };
}
