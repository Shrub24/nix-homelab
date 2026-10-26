# Base OS policy, users, Nix tuning, and the two machine facts hosts declare instead of
# fighting shared defaults with mkForce: fleet.foundation.{bootLoader,buildTmpfsSize}.
{ inputs, ... }:
{
  flake.modules.nixos.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # An absent host system scope keeps the two-step sops bootstrap working.
      hostSystemSecret = ../../secrets/hosts + "/${config.networking.hostName}/system.yaml";
      hasHostSecrets = builtins.pathExists hostSystemSecret;

      foundation = config.fleet.foundation;
      hostIdentity = config.fleet.hostIdentity;

      hasGithubToken =
        (import ../../lib/sops-keys.nix { inherit lib; }).hasKey config.sops.defaultSopsFile "github"
          "token";

      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFBqFsxbrn6SVOHXi4+LS5olKxEW8JlZ5V+irA18/586 saurabhj@arch"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMrzW7nXTeKqejlnIYmccciDJ4/PfjV6ek4Wvo7v86/a termix"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBsHnolkmLVudDN3HKQ/Q4Xw2ZqDVjax177hbi15jqRW la-admin-1-dev@shrublab"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINRh71N504a6X1OkZ6XxhJrllHiEEWC/4o5s3+RtPuI8 home-forge-dev@shrublab"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBeKFT2RvMo1WvF+f8Q6W8cU2wn31aCG1k9onz6Y+fqz root@arch"
      ];
    in
    {
      imports = [
        inputs.nix-fleet.modules.nixos.nix-baseline
        inputs.nix-fleet.modules.nixos.nix-gc
      ];

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

        # Outbound dev SSH identity: the conventional host-scoped default is
        # derived here instead of in each host record.
        fleet.hostIdentity.sshPrivateKeyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Host-scoped SOPS file containing the dev user SSH identity private key.";
        };
      };

      config = {
        # The fleet's nix-baseline owns the package, daemon priority, connection
        # tuning and the substitution catalog; the cache list lives there, not here.
        nix.settings = {
          trusted-users = [
            "root"
            "dev"
          ];
          max-jobs = 2;
          cores = 0;
        };

        # nix.conf is world-readable, so the token reaches the daemon through an included
        # file instead; without it the anonymous GitHub budget stays in place.
        sops.secrets."github/token" = lib.mkIf hasGithubToken { };

        sops.templates."nix-access-tokens.conf" = lib.mkIf hasGithubToken {
          content = "access-tokens = github.com=${config.sops.placeholder."github/token"}\n";
          restartUnits = [ "nix-daemon.service" ];
        };

        nix.extraOptions = lib.mkIf hasGithubToken (
          "!include ${config.sops.templates."nix-access-tokens.conf".path}"
        );

        time.timeZone = "UTC";

        # No host declares a swap device; compressed RAM absorbs a build or database
        # spike without writing to the data disk.
        zramSwap.enable = true;

        services.journald.settings.Journal = {
          SystemMaxUse = "300M";
          SystemKeepFree = "1G";
          MaxRetentionSec = "7day";
        };

        # A crash loop on a multi-second cycle never trips the default 5 starts / 10s and
        # blocks activation instead, so bound it at five an hour.
        systemd.services = lib.mapAttrs' (
          name: _:
          lib.nameValuePair "podman-${name}" {
            startLimitIntervalSec = 3600;
            startLimitBurst = 5;
          }
        ) config.virtualisation.oci-containers.containers;

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

        users = {
          mutableUsers = false;

          users.dev = {
            isNormalUser = true;
            description = "Dev User";
            # `notify` grants unix-socket dispatch: `just deploy` sends its outcome
            # notification through the target host's notify CLI as this user.
            extraGroups = [
              "wheel"
            ]
            ++ lib.optionals (config.users.groups ? notify) [ "notify" ];
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

        services.udev.extraRules = ''
          ACTION=="add|change", KERNEL=="sd[a-z]|vd[a-z]", ATTR{queue/scheduler}="mq-deadline"
        '';

        # No override: restating a weaker schedule here would silently disable upstream's
        # root pruning.

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
        sops.secrets.host_ssh_identity_raw = lib.mkIf (hostIdentity.sshPrivateKeyFile != null) {
          sopsFile = hostIdentity.sshPrivateKeyFile;
          key = "identity/ssh_private_key";
          mode = "0400";
        };
      };
    };
}
