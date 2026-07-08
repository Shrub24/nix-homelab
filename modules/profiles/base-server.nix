{ config, lib, ... }:
let
  globals = import ../../policy/globals.nix;
  nixPolicy = globals.services.nix or { };
  cfg = config.fleet.hostIdentity;
in
{
  imports = [
    ../core/base.nix
    ./shell-profile.nix
    ../shared/host-recovery.nix
    ../services/tailscale.nix
    ../services/beszel-agent-auth.nix
    ../services/state-backups.nix
  ];

  options.fleet.hostIdentity.sshPrivateKeyFile = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = "Host-scoped SOPS file containing the dev user SSH identity private key.";
  };

  config = {
    networking.firewall.allowedTCPPorts = lib.mkDefault [ 22 ];
    networking.firewall.trustedInterfaces = lib.mkAfter [ "tailscale0" ];

    nix.settings = {
      substituters = lib.mkAfter (nixPolicy.substituters or [ ]);
      trusted-substituters = lib.mkAfter (nixPolicy.trustedSubstituters or [ ]);
      trusted-public-keys = lib.mkAfter (nixPolicy.trustedPublicKeys or [ ]);
      max-jobs = 2;
      cores = 0;
      max-substitution-jobs = 8;
      http-connections = 64;
      download-buffer-size = 268435456;
    };

    fileSystems."/build" = {
      fsType = "tmpfs";
      options = [
        "size=8G"
        "mode=0755"
      ];
    };

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

    programs.ssh.extraConfig = lib.mkIf (cfg.sshPrivateKeyFile != null) ''
      Host *
        IdentityFile /run/secrets/host.ssh_identity
        IdentitiesOnly yes
    '';

    sops.templates."host-ssh-identity" = lib.mkIf (cfg.sshPrivateKeyFile != null) {
      content = ''
        ${config.sops.placeholder.host_ssh_identity_raw}
      '';
      path = "/run/secrets/host.ssh_identity";
      mode = "0400";
    };
    sops.secrets = lib.mkIf (cfg.sshPrivateKeyFile != null) {
      host_ssh_identity_raw = {
        sopsFile = cfg.sshPrivateKeyFile;
        key = "identity/ssh_private_key";
        mode = "0400";
      };
    };
  };
}
