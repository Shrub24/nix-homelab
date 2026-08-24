{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.navidrome;
  libraryDir = if cfg.libraryDir != null then cfg.libraryDir else "${cfg.mediaRoot}/library";
  quarantineDir =
    if cfg.quarantineDir != null then cfg.quarantineDir else "${cfg.mediaRoot}/quarantine";

  # ── Operator-managed (not repo-declared) ──────────────────────────────
  # AudioMuse plugin configuration after the binary is installed:
  #   - Navidrome Admin → Plugins → audiomuse.ai: enable, set API URL, key
  #   - AudioMuse first-run setup wizard (web UI on :8000)
  #   - Symfonium → Navidrome connection: configure as OpenSubsonic server
  # These settings reside in Navidrome's application state (DB) and cannot
  # be seeded declaratively until upstream exposes a stable import path.
  # ──────────────────────────────────────────────────────────────────────────
in
{
  options.services.navidrome.mediaRoot = lib.mkOption {
    type = lib.types.str;
    default = "/srv/media";
    description = "Root directory for media files";
  };

  options.services.navidrome.dataDir = lib.mkOption {
    type = lib.types.str;
    default = "/srv/data/navidrome";
    description = "Data directory for Navidrome";
  };

  options.services.navidrome.libraryDir = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "Primary Navidrome library path (defaults to mediaRoot + /library).";
  };

  options.services.navidrome.quarantineDir = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "Secondary Navidrome library path for quarantine (defaults to mediaRoot + /quarantine).";
  };

  options.services.navidrome.audiomuse = {
    enable = lib.mkEnableOption "AudioMuseAI Navidrome plugin wiring";
    devArtistInfoTimeToLive = lib.mkOption {
      type = lib.types.str;
      default = "1s";
      description = "Navidrome artist-info TTL required by the AudioMuseAI plugin path.";
    };
  };

  config = {
    services.navidrome = {
      enable = true;
      openFirewall = false;
      plugins = lib.mkIf cfg.audiomuse.enable [ pkgs.navidromePlugins.audiomuseai ];
      settings = lib.mkMerge [
        {
          MusicFolder = lib.mkDefault libraryDir;
          DataFolder = lib.mkDefault config.services.navidrome.dataDir;
          ScanSchedule = "15m";
          EnableTranscodingConfig = true;
          EnableSharing = true;
          DefaultDownsamplingFormat = "opus";
          TranscodingCacheSize = "2GB";
          FFmpegPath = "${pkgs.ffmpeg}/bin/ffmpeg";
          Address = "0.0.0.0";
          PID.Album = "albumartistid,album";
        }
        (lib.mkIf cfg.audiomuse.enable {
          Plugins = {
            Enabled = true;
            AutoReload = true;
          };
          Agents = "audiomuseai";
          DevArtistInfoTimeToLive = cfg.audiomuse.devArtistInfoTimeToLive;
        })
      ];
    };

    systemd.tmpfiles.settings.navidromeDirs."${cfg.settings.DataFolder or "/var/lib/navidrome"}"."d" = {
      mode = "700";
      user = cfg.user;
      group = cfg.group;
    };
    systemd.tmpfiles.settings.navidromeDirs."${cfg.settings.CacheFolder or "/var/lib/navidrome/cache"
    }"."d" =
      {
        mode = "700";
        user = cfg.user;
        group = cfg.group;
      };

    systemd.services.navidrome = {
      unitConfig.RequiresMountsFor = [
        libraryDir
        quarantineDir
        cfg.dataDir
      ];
      wants = [
        "network-online.target"
        "syncthing.service"
      ];
      after = [
        "network-online.target"
        "syncthing.service"
      ];
      serviceConfig.ReadWritePaths = lib.mkAfter [
        libraryDir
        quarantineDir
      ];
      serviceConfig.PrivateMounts = lib.mkForce false;
      serviceConfig.SupplementaryGroups = lib.mkAfter [
        "media"
        "music-ingest"
      ];
    };

    systemd.services.navidrome-scan = {
      description = "Scan Navidrome music library";
      after = [ "navidrome.service" ];
      unitConfig.RequiresMountsFor = [
        libraryDir
        cfg.dataDir
      ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        SupplementaryGroups = [
          "media"
          "music-ingest"
        ];
        ExecStart = "${cfg.package}/bin/navidrome --nobanner --datafolder ${cfg.dataDir} --musicfolder ${libraryDir} scan";
      };
    };
  };
}
