# Navidrome aspect contributor: composed by the music coordinator aspect
# by flake-level import; this file owns the feature body.
_: {
  flake.modules.nixos.music =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.services.navidrome;

      # Extism wasm: the plugin must come from the wasi32 cross set. Asking the host set
      # links -buildmode=c-shared against the host, which the toolchain cannot link.
      audiomuseaiPlugin = pkgs.pkgsCross.wasi32.navidromePlugins.audiomuseai;

      # Post-install plugin steps: docs/runbooks/music.md.
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

      options.services.navidrome.extraDirs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional media directories to expose (read-write) in the Navidrome mount namespace.";
      };

      options.services.navidrome.audiomuse = {
        enable = lib.mkEnableOption "AudioMuseAI Navidrome plugin wiring";
        devArtistInfoTimeToLive = lib.mkOption {
          type = lib.types.str;
          default = "1s";
          description = "Navidrome artist-info TTL required by the AudioMuseAI plugin path.";
        };
      };

      # Gated on nixpkgs' flag, so a host that imports this leaf without music enabled
      # leaves no dormant units behind.
      config = lib.mkIf config.services.navidrome.enable {
        # Pinned: state moves between hosts, and NixOS allocation is host-dependent.
        users.users.navidrome.uid = lib.mkDefault 977;
        users.groups.navidrome.gid = lib.mkDefault 977;

        services.navidrome = {
          openFirewall = false;
          # Symlinked via tmpfiles rather than set through services.navidrome.plugins, which
          # would bake the plugin into the build and lose the cache-substitutable package.
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
          inherit (cfg) user;
          inherit (cfg) group;
        };
        systemd.tmpfiles.settings.navidromeDirs."${cfg.settings.CacheFolder or "/var/lib/navidrome/cache"
        }"."d" =
          {
            mode = "700";
            inherit (cfg) user;
            inherit (cfg) group;
          };

        # The .ndp symlink keeps the stock package; see the note above.
        systemd.tmpfiles.settings.navidromeDirs."${cfg.dataDir}/plugins" = {
          "d" = {
            mode = "700";
            inherit (cfg) user;
            inherit (cfg) group;
          };
        };
        systemd.tmpfiles.settings.navidromeDirs."${cfg.dataDir}/plugins/audiomuseai.ndp" = {
          "L+" = {
            argument = "${audiomuseaiPlugin}/share/audiomuseai.ndp";
          };
        };

        systemd.services.navidrome = {
          unitConfig.RequiresMountsFor = [
            cfg.libraryDir
            cfg.quarantineDir
            cfg.dataDir
          ]
          ++ cfg.extraDirs;
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
          # RootDirectory=/run/navidrome means only bind-mounted paths exist, so MusicFolder,
          # secondary libraries and Plugins.Folder all need binds.
          serviceConfig.BindReadOnlyPaths = lib.mkAfter (
            [
              cfg.quarantineDir
              "${cfg.dataDir}/plugins:${config.services.navidrome.finalPackage}/share/plugins"
            ]
            ++ cfg.extraDirs
          );
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
    };
}
