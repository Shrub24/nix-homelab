# Music-ingest aspect contributor: owns the ingest mechanisms — the
# ffmpeg-preprocess binary/service, the dropbox path unit and debounce
# poke/timers, the scoped slskd-settle polkit rule, and the slskd completion
# hook. Composed by the music coordinator aspect by flake-level import; never
# host-imported.
{ ... }:
{
  flake.modules.nixos.music =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.services.musicIngest;

      ffmpegPreprocessBin = pkgs.writeShellApplication {
        name = "ffmpeg-preprocess";
        runtimeInputs = [
          pkgs.ffmpeg
          pkgs.findutils
          pkgs.coreutils
        ];
        text = builtins.readFile ./files/ffmpeg-preprocess.sh;
      };

      slskdDownloadCompleteHook = pkgs.writeShellScript "slskd-download-complete" ''
        export PATH="/run/current-system/sw/bin:$PATH"
        exec systemctl try-restart slskd-settle.timer
      '';
    in
    {
      options.services.musicIngest = {
        enable = lib.mkEnableOption "music ingest pipeline (ffmpeg preprocess, settle timers, slskd completion hook)";

        inboxDir = lib.mkOption {
          type = lib.types.str;
          description = "Inbox root watched for incoming media. Required; injected by the composition.";
        };

        storageRoot = lib.mkOption {
          type = lib.types.str;
          description = "Media storage root the inbox lives under (mount prerequisite). Required; injected by the composition.";
        };

        stateDirectory = lib.mkOption {
          type = lib.types.str;
          default = "beets/ffmpeg-preprocess";
          description = "systemd StateDirectory for the preprocess service; the import-ready flag derives from it.";
        };

        readyFlag = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default = "/var/lib/${cfg.stateDirectory}/inbox-ready";
          description = "Import-ready flag the preprocess touches; consumed by the composition as the beets import gate.";
        };

        onSuccessUnit = lib.mkOption {
          type = lib.types.str;
          default = "beets-inbox.service";
          description = "Unit chained via OnSuccess= after a successful preprocess pass.";
        };

        downloadCompleteScript = lib.mkOption {
          type = lib.types.path;
          readOnly = true;
          default = slskdDownloadCompleteHook;
          description = "slskd DownloadDirectoryComplete hook script; assigned by the composition to services.slskd.downloadCompleteScript.";
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.services.ffmpeg-preprocess = {
          description = "Pre-process incoming audio to library formats before import";
          after = [ "network.target" ];
          unitConfig = {
            OnSuccess = cfg.onSuccessUnit;
          };
          serviceConfig = {
            Type = "oneshot";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            MemoryDenyWriteExecute = true;
            RestrictRealtime = true;
            SystemCallArchitectures = "native";
            ExecStart = "${ffmpegPreprocessBin}/bin/ffmpeg-preprocess ${cfg.inboxDir}";
            Environment = [
              "PATH=/run/current-system/sw/bin"
            ];
            User = "beets";
            Group = "beets";
            StateDirectory = cfg.stateDirectory;
            WorkingDirectory = "${cfg.inboxDir}";
            ReadWritePaths = [ cfg.inboxDir ];
          };
        };

        # Unit= is a [Path]-section key (pathConfig), not a [Unit] key.
        systemd.paths.dropbox-inbox = {
          enable = true;
          wantedBy = [ "multi-user.target" ];
          unitConfig.RequiresMountsFor = cfg.storageRoot;
          pathConfig = {
            PathModified = "${cfg.inboxDir}/dropbox";
            Unit = "dropbox-poke.service";
          };
        };

        systemd.services.dropbox-poke = {
          description = "Re-arm the dropbox settle timer (debounce trickle writes)";
          path = [ pkgs.systemd ];
          serviceConfig = {
            Type = "oneshot";
            # restart, not try-restart: a fired one-shot timer is inactive, and the event must always schedule a run.
            ExecStart = "systemctl restart dropbox-settle.timer";
          };
        };

        systemd.timers.dropbox-settle = {
          enable = true;
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnActiveSec = "60s";
            AccuracySec = "5s";
            Persistent = true;
            Unit = "ffmpeg-preprocess.service";
          };
        };

        systemd.timers.slskd-settle = {
          enable = true;
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnActiveSec = "60s";
            AccuracySec = "5s";
            Persistent = true;
            Unit = "ffmpeg-preprocess.service";
          };
        };

        # Grant the unprivileged slskd user exactly one unit action: re-arm the settle timer.
        security.polkit.extraConfig = ''
          polkit.addRule(function(action, subject) {
              if (action.id == "org.freedesktop.systemd1.manage-units"
                  && subject.user == "slskd"
                  && action.lookup("unit") == "slskd-settle.timer") {
                  return polkit.Result.YES;
              }
          });
        '';

        environment.systemPackages = [ ffmpegPreprocessBin ];
      };
    };
}
