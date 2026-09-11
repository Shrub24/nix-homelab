{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.hostRecovery;
  passwordlessRuleFor = user: {
    users = [ user ];
    commands = [
      {
        command = "ALL";
        options = [ "NOPASSWD" ];
      }
    ];
  };
in
{
  options.services.hostRecovery = {
    enable = lib.mkEnableOption "console-oriented host recovery baseline";

    secretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to the host-scoped SOPS file containing recovery secrets.";
    };

    secretKeys = {
      rescuePasswordHash = lib.mkOption {
        type = lib.types.str;
        default = "recovery/rescue_password_hash";
        description = "SOPS key path for the rescue user's password hash.";
      };
    };

    rescueUser = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "rescue";
      };

      description = lib.mkOption {
        type = lib.types.str;
        default = "Break-glass console recovery user";
      };

      shell = lib.mkOption {
        type = lib.types.package;
        default = pkgs.bashInteractive;
      };
    };

    reboot = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };

      onCalendar = lib.mkOption {
        type = lib.types.str;
        default = "weekly";
      };

      randomizedDelaySec = lib.mkOption {
        type = lib.types.str;
        default = "1h";
      };

      persistent = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
    };

    passwordlessSudoUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "dev" ];
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.rescueUser.enable || cfg.secretFile != null;
        message = "Set services.hostRecovery.secretFile when rescue user recovery is enabled.";
      }
    ];

    sops.secrets = lib.optionalAttrs cfg.rescueUser.enable {
      host_recovery_rescue_password_hash = {
        sopsFile = cfg.secretFile;
        key = cfg.secretKeys.rescuePasswordHash;
        path = "/run/secrets/host-recovery.rescue_password_hash";
        neededForUsers = true;
        owner = "root";
        group = "root";
        mode = "0400";
      };
    };

    users.users = lib.optionalAttrs cfg.rescueUser.enable {
      "${cfg.rescueUser.name}" = {
        isNormalUser = true;
        description = cfg.rescueUser.description;
        extraGroups = [ "wheel" ];
        shell = "${cfg.rescueUser.shell}/bin/bash";
        hashedPasswordFile = config.sops.secrets.host_recovery_rescue_password_hash.path;
      };
    };

    security.sudo = {
      wheelNeedsPassword = lib.mkForce true;
      extraRules = map passwordlessRuleFor cfg.passwordlessSudoUsers;
    };

    services.openssh.extraConfig = lib.mkIf cfg.rescueUser.enable (
      lib.mkAfter ''
        Match User ${cfg.rescueUser.name}
          PasswordAuthentication no
          KbdInteractiveAuthentication no
          PubkeyAuthentication no
      ''
    );

    systemd.services.host-recovery-reboot = lib.mkIf cfg.reboot.enable {
      description = "Scheduled host recovery reboot exercise";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl reboot";
      };
    };

    systemd.timers.host-recovery-reboot = lib.mkIf cfg.reboot.enable {
      description = "Scheduled host recovery reboot exercise";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.reboot.onCalendar;
        RandomizedDelaySec = cfg.reboot.randomizedDelaySec;
        Persistent = cfg.reboot.persistent;
      };
    };
  };
}
