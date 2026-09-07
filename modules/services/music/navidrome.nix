{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.navidrome;

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
  options.services.navidrome.dataDir = lib.mkOption {
    type = lib.types.str;
    description = "Data directory for Navidrome. Required; injected by the caller.";
  };

  options.services.navidrome.libraryDir = lib.mkOption {
    type = lib.types.str;
    description = "Primary Navidrome library path. Required; injected by the caller.";
  };

  options.services.navidrome.quarantineDir = lib.mkOption {
    type = lib.types.str;
    description = "Secondary Navidrome library path for quarantine. Required; injected by the caller.";
  };

  options.services.navidrome.audiomuse = {
    enable = lib.mkEnableOption "AudioMuseAI Navidrome plugin wiring";
    devArtistInfoTimeToLive = lib.mkOption {
      type = lib.types.str;
      default = "1s";
      description = "Navidrome artist-info TTL required by the AudioMuseAI plugin path.";
    };
  };

  # Gate the entire custom Navidrome composition (settings, units, tmpfiles) on
  # nixpkgs' services.navidrome.enable. A host that wants Navidrome must set it
  # explicitly; hosts that only import this leaf (e.g. OCI via applications.music)
  # can disable it cleanly without leaving dormant units or settings behind.
  config = lib.mkIf config.services.navidrome.enable {
    # Fleet-stable identity: Navidrome state moves between hosts, so the
    # numeric UID/GID is pinned instead of left to per-host dynamic
    # allocation (NixOS descends from 999, host-dependent).
    users.users.navidrome.uid = lib.mkDefault 977;
    users.groups.navidrome.gid = lib.mkDefault 977;

    services.navidrome = {
      openFirewall = false;
      # Cache-preserving AudioMuseAI plugin integration: we deliberately do NOT
      # use `services.navidrome.plugins = [ pkgs.navidromePlugins.audiomuseai ]`
      # because that bakes the plugin derivation into the Navidrome build and
      # loses the stock cache-substitutable Navidrome. Instead we declaratively
      # symlink the packaged WASM `.ndp` into ${dataDir}/plugins via tmpfiles and
      # bind it into nixpkgs' fixed Plugins.Folder below.
      settings = lib.mkMerge [
        {
          MusicFolder = lib.mkDefault cfg.libraryDir;
          DataFolder = lib.mkDefault config.services.navidrome.dataDir;
          ScanSchedule = "15m";
          EnableTranscodingConfig = true;
          EnableSharing = true;
          DefaultDownsamplingFormat = "opus";
          TranscodingCacheSize = "2GB";
          FFmpegPath = "${pkgs.ffmpeg}/bin/ffmpeg";
          Address = "0.0.0.0";
          PID.Album = "albumartistid,album";
          Subsonic = {
            DefaultReportRealPath = true;
          };
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

    # AudioMuseAI plugin directory + packaged WASM `.ndp` symlink (cache-preserving).
    # The plugin file is provided by pkgs.navidromePlugins.audiomuseai; symlinking
    # into ${cfg.dataDir}/plugins avoids embedding it in the Navidrome derivation so
    # stock cache-substitutable Navidrome is retained.
    systemd.tmpfiles.settings.navidromeDirs."${cfg.dataDir}/plugins" = {
      "d" = {
        mode = "700";
        user = cfg.user;
        group = cfg.group;
      };
    };
    systemd.tmpfiles.settings.navidromeDirs."${cfg.dataDir}/plugins/audiomuseai.ndp" = {
      "L+" = {
        argument = "${pkgs.navidromePlugins.audiomuseai}/share/audiomuseai.ndp";
      };
    };

    systemd.services.navidrome = {
      unitConfig.RequiresMountsFor = [
        cfg.libraryDir
        cfg.quarantineDir
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
        cfg.libraryDir
        cfg.quarantineDir
      ];
      # nixpkgs fixes Plugins.Folder at finalPackage/share/plugins. Bind the
      # declarative data-dir link there only in Navidrome's mount namespace so
      # the cached stock package remains immutable and cache-substitutable.
      serviceConfig.BindReadOnlyPaths = lib.mkAfter [
        "${cfg.dataDir}/plugins:${config.services.navidrome.finalPackage}/share/plugins"
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
        cfg.libraryDir
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
        ExecStart = "${cfg.package}/bin/navidrome --nobanner --datafolder ${cfg.dataDir} --musicfolder ${cfg.libraryDir} scan";
      };
    };
  };
}
