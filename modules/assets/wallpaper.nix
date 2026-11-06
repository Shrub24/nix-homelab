_: {
  # Replaces the object behind the fixed wallpaper URL with a random candidate from the bucket.
  flake.modules.nixos.assets-publisher =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      policy = import ../../policy/assets.nix;
      cfg = config.services.assets.wallpaper;
      spec = pkgs.writeText "assets-wallpaper.json" (
        builtins.toJSON {
          inherit (policy) bucket endpoint;
          inherit (cfg) prefix key cacheControl;
          inherit (policy.brand.wallpaper) url;
          inherit (policy) zoneName;
        }
      );
      python = pkgs.python3.withPackages (ps: [ ps.boto3 ]);
      scripts = import ./_scripts.nix { inherit lib; };
    in
    {
      options.services.assets.wallpaper = {
        enable = lib.mkEnableOption "the published-background rotator; one host may own it, since two rotators overwrite each other";
        key = lib.mkOption {
          type = lib.types.str;
          default = lib.removePrefix "${policy.publicUrl}/" policy.brand.wallpaper.url;
          defaultText = lib.literalExpression "the bucket key behind brand.wallpaper.url";
          description = "Object key the chosen candidate replaces.";
        };
        prefix = lib.mkOption {
          type = lib.types.str;
          default = "backgrounds/";
          description = "Bucket prefix holding the candidate images.";
        };
        cacheControl = lib.mkOption {
          type = lib.types.str;
          default = "public, max-age=300";
          description = "Cache lifetime the published object carries, which bounds how long a rotation can stay invisible.";
        };
        interval = lib.mkOption {
          type = lib.types.str;
          default = "daily";
          description = "systemd OnCalendar expression for the rotation.";
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.services.assets-wallpaper = {
          description = "Replace the published background with a random candidate";
          # Activation picks one too, so the object exists before the first timer elapse.
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [
            "network-online.target"
            "sops-install-secrets.service"
          ];
          restartTriggers = [
            spec
            config.sops.templates."assets-publisher.env".path
          ];
          serviceConfig = {
            Type = "oneshot";
            Restart = "no";
            TimeoutStartSec = 180;
            EnvironmentFile = config.sops.templates."assets-publisher.env".path;
            Environment = [
              "AWS_EC2_METADATA_DISABLED=true"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
            ExecStart = "${python}/bin/python ${scripts}/_rotate.py ${spec}";
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
          };
        };

        systemd.timers.assets-wallpaper = {
          description = "Rotate the published background";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.interval;
            RandomizedDelaySec = "4h";
            Persistent = true;
          };
        };
      };
    };
}
