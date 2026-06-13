{
  lib,
  config,
  pkgs,
  ociImages,
  ...
}:
let
  cfg = config.services.soulsync;
  secretHelpers = import ../../lib/secrets.nix { inherit lib; };
  inherit (lib)
    mkIf
    optionalAttrs
    optional
    optionals
    ;
in
{
  options.services.soulsync = {
    enable = lib.mkEnableOption "SoulSync ingest service";

    image = lib.mkOption {
      type = lib.types.str;
      default = ociImages.soulsync;
      description = "Pinned SoulSync container image.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/srv/data/soulsync";
      description = "Persistent data directory for SoulSync.";
    };

    mediaRoot = lib.mkOption {
      type = lib.types.str;
      default = "/srv/media";
      description = "Media root used to derive SoulSync path defaults.";
    };

    downloadPath = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.mediaRoot}/inbox/slskd";
      description = "Host download path consumed by SoulSync.";
    };

    transferPath = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.mediaRoot}/library";
      description = "Host transfer/library path used by SoulSync.";
    };

    stagingPath = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.mediaRoot}/quarantine/approved";
      description = "Host import staging path used by SoulSync.";
    };

    unresolvedPath = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.mediaRoot}/quarantine/untagged";
      description = "Host unresolved/review path retained for operator fallback flow.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Listen address for SoulSync container port mapping.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8008;
      description = "SoulSync web UI port on the host.";
    };

    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "UTC";
      description = "Timezone passed into SoulSync container.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional env-file with required SoulSync credentials and runtime values.";
    };

    optionalEnvironmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Optional additional env-files (provider-specific) loaded only when present.";
    };

    configTemplateFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional rendered config template copied into dataDir/config.json before container start.";
    };

    conservativeDefaults = {
      metadataFallbackSource = lib.mkOption {
        type = lib.types.enum [
          "deezer"
          "itunes"
          "spotify"
          "discogs"
          "hydrabase"
        ];
        default = "discogs";
        description = "Preferred primary metadata fallback source for rollout defaults.";
      };

      disableBroadRepairJobs = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Conservative rollout guard documented for pre-existing library mutation posture.";
      };

      controlPlaneOnly = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Control-plane-first posture flag for public exposure and playback suppression intent.";
      };
    };

    secretFiles.host = secretHelpers.mkSecretFileOption "soulsync-host-secrets";
  };

  config = mkIf cfg.enable (
    let
      hasHostSecrets = cfg.secretFiles.host != null;
    in
    {
      assertions = [
        (secretHelpers.mkRequiredSecretAssertion {
          enable = cfg.enable;
          file = cfg.secretFiles.host;
          feature = "services.soulsync";
          label = "secretFiles.host";
        })
      ];

      sops.templates."soulsync.env" = {
        owner = "root";
        group = "root";
        mode = "0400";
        content = ''
          SLSKD_API_KEY=${config.sops.placeholder.soulsync_slskd_api_key}
          SOULSYNC_DISCOGS_TOKEN=${config.sops.placeholder.soulsync_discogs_token}
          SOULSYNC_NAVIDROME_USERNAME=${config.sops.placeholder.soulsync_navidrome_username}
          SOULSYNC_NAVIDROME_PASSWORD=${config.sops.placeholder.soulsync_navidrome_password}
        '';
      };

      sops.templates."soulsync-config.json" = {
        owner = "root";
        group = "root";
        mode = "0400";
        content = ''
          {
            "active_media_server": "navidrome",
            "metadata": {
              "fallback_source": "discogs"
            },
            "discogs": {
              "token": "${config.sops.placeholder.soulsync_discogs_token}"
            },
            "soulseek": {
              "slskd_url": "http://host.containers.internal:5030",
              "api_key": "${config.sops.placeholder.soulsync_slskd_api_key}",
              "download_path": "${cfg.mediaRoot}/inbox/slskd",
              "transfer_path": "${cfg.mediaRoot}/library"
            },
            "import": {
              "staging_path": "${cfg.mediaRoot}/quarantine/approved",
              "replace_lower_quality": false
            },
            "navidrome": {
              "base_url": "http://host.containers.internal:4533",
              "username": "${config.sops.placeholder.soulsync_navidrome_username}",
              "password": "${config.sops.placeholder.soulsync_navidrome_password}",
              "auto_detect": true
            }
          }
        '';
      };

      sops.templates."soulsync-spotify.env" = mkIf hasHostSecrets {
        owner = "root";
        group = "root";
        mode = "0400";
        content = ''
          SOULSYNC_SPOTIFY_CLIENT_ID=${config.sops.placeholder.soulsync_spotify_client_id}
          SOULSYNC_SPOTIFY_CLIENT_SECRET=${config.sops.placeholder.soulsync_spotify_client_secret}
        '';
      };

      sops.templates."soulsync-deezer.env" = mkIf hasHostSecrets {
        owner = "root";
        group = "root";
        mode = "0400";
        content = ''
          SOULSYNC_DEEZER_ARL=${config.sops.placeholder.soulsync_deezer_arl}
        '';
      };

      sops.templates."soulsync-youtube.env" = mkIf hasHostSecrets {
        owner = "root";
        group = "root";
        mode = "0400";
        content = ''
          SOULSYNC_YOUTUBE_COOKIES=${config.sops.placeholder.soulsync_youtube_cookies}
        '';
      };

      sops.secrets = {
        soulsync_slskd_api_key = {
          sopsFile = cfg.secretFiles.host;
          key = "soulsync/slskd_api_key";
          path = "/run/secrets/soulsync.slskd_api_key";
        };
        soulsync_discogs_token = {
          sopsFile = cfg.secretFiles.host;
          key = "soulsync/discogs_token";
          path = "/run/secrets/soulsync.discogs_token";
        };
        soulsync_navidrome_username = {
          sopsFile = cfg.secretFiles.host;
          key = "soulsync/navidrome_username";
          path = "/run/secrets/soulsync.navidrome_username";
        };
        soulsync_navidrome_password = {
          sopsFile = cfg.secretFiles.host;
          key = "soulsync/navidrome_password";
          path = "/run/secrets/soulsync.navidrome_password";
        };
      }
      // optionalAttrs hasHostSecrets {
        soulsync_spotify_client_id = {
          sopsFile = cfg.secretFiles.host;
          key = "soulsync/spotify_client_id";
          path = "/run/secrets/soulsync.spotify_client_id";
        };
        soulsync_spotify_client_secret = {
          sopsFile = cfg.secretFiles.host;
          key = "soulsync/spotify_client_secret";
          path = "/run/secrets/soulsync.spotify_client_secret";
        };
        soulsync_deezer_arl = {
          sopsFile = cfg.secretFiles.host;
          key = "soulsync/deezer_arl";
          path = "/run/secrets/soulsync.deezer_arl";
        };
        soulsync_youtube_cookies = {
          sopsFile = cfg.secretFiles.host;
          key = "soulsync/youtube_cookies";
          path = "/run/secrets/soulsync.youtube_cookies";
        };
      };

      virtualisation.podman.enable = true;

      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0750 root root - -"
        "d ${cfg.dataDir}/logs 0750 root root - -"
        "d ${cfg.stagingPath} 2775 root music-ingest - -"
        "d ${cfg.unresolvedPath} 2775 root music-ingest - -"
        "a+ ${cfg.unresolvedPath} - - - - group:music-ingest:rwx"
        "a+ ${cfg.unresolvedPath} - - - - default:group:music-ingest:rwX"
        "a+ ${cfg.unresolvedPath} - - - - group:media:r-X"
        "a+ ${cfg.unresolvedPath} - - - - default:group:media:r-X"
        "a+ ${cfg.stagingPath} - - - - group:music-ingest:rwx"
        "a+ ${cfg.stagingPath} - - - - default:group:music-ingest:rwX"
        "a+ ${cfg.stagingPath} - - - - group:media:r-X"
        "a+ ${cfg.stagingPath} - - - - default:group:media:r-X"
      ];

      systemd.services.soulsync-config = mkIf (cfg.configTemplateFile != null) {
        description = "Render SoulSync config from host template";
        wantedBy = [ "multi-user.target" ];
        before = [ "podman-soulsync.service" ];
        unitConfig = {
          RequiresMountsFor = [ cfg.dataDir ];
          ConditionPathExists = cfg.configTemplateFile;
        };
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "soulsync-config-render" ''
            set -euo pipefail
            install -d -m 0750 "${cfg.dataDir}"
            install -m 0640 "${cfg.configTemplateFile}" "${cfg.dataDir}/config.json"
          '';
        };
      };

      virtualisation.oci-containers.containers.soulsync = {
        autoStart = true;
        image = cfg.image;
        ports = [
          "${cfg.listenAddress}:${toString cfg.port}:8008"
        ];
        environment = {
          FLASK_ENV = "production";
          PUID = "1000";
          PGID = toString config.users.groups.music-ingest.gid;
          PYTHONPATH = "/app";
          TZ = cfg.timeZone;
          SOULSYNC_CONFIG_PATH = "/app/data/config.json";
          SOULSYNC_SPOTIFY_CALLBACK_PORT = "8888";
          SOULSYNC_TIDAL_CALLBACK_PORT = "8889";
          SOULSYNC_CONTROL_PLANE_ONLY = if cfg.conservativeDefaults.controlPlaneOnly then "1" else "0";
          SOULSYNC_DISABLE_BROAD_REPAIR_JOBS =
            if cfg.conservativeDefaults.disableBroadRepairJobs then "1" else "0";
          SOULSYNC_METADATA_FALLBACK_SOURCE = cfg.conservativeDefaults.metadataFallbackSource;
        };
        environmentFiles =
          optionals (cfg.environmentFile != null) [ cfg.environmentFile ] ++ cfg.optionalEnvironmentFiles;
        extraOptions = [
          "--dns-search=tail0fe19b.ts.net"
        ];
        volumes = [
          "${cfg.dataDir}:/app/data"
          "${cfg.downloadPath}:${cfg.downloadPath}:rw"
          "${cfg.transferPath}:${cfg.transferPath}:rw"
          "${cfg.stagingPath}:${cfg.stagingPath}:rw"
          "${cfg.unresolvedPath}:${cfg.unresolvedPath}:rw"
        ];
      };

      systemd.services."podman-soulsync" = {
        wants = [
          "network-online.target"
        ]
        ++ optionals (cfg.configTemplateFile != null) [ "soulsync-config.service" ];
        after = [
          "network-online.target"
        ]
        ++ optionals (cfg.configTemplateFile != null) [ "soulsync-config.service" ];
        unitConfig.RequiresMountsFor = [
          cfg.dataDir
          cfg.downloadPath
          cfg.transferPath
          cfg.stagingPath
          cfg.unresolvedPath
        ];
        serviceConfig.SupplementaryGroups = lib.mkAfter [ "music-ingest" ];
      };
    }
  );
}
