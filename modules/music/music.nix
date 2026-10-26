# Music aspect: composition only. Selection is enablement.
# Mechanisms are discovered aspects composed here; DJ consumes the read-only `applications.music.contract`.
_: {
  flake.modules.nixos.music =
    {
      lib,
      config,
      options,
      ...
    }:
    let
      cfg = config.applications.music;
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };

      # The database is the host's own cluster; a host without one must set `audiomuse.postgresHost`.
      # Probed through `options`: reading an undeclared path throws instead of returning null.
      hasLocalCluster = lib.hasAttrByPath [ "services" "postgres" "localEndpoint" ] options;
      localPostgres = if hasLocalCluster then config.services.postgres.localEndpoint else null;
      serviceNetwork = (import ../../policy/globals.nix).serviceNetwork;
      audiomusePostgres = {
        host = serviceNetwork.hostName;
        port = if localPostgres != null then localPostgres.port else 5432;
      };

      mediaPaths = rec {
        libraryDir = "${cfg.storageRoot}/library";
        playlistsDir = "${cfg.storageRoot}/playlists";
        inboxDir = "${cfg.storageRoot}/inbox";
        quarantineDir = "${cfg.storageRoot}/quarantine";
        versionArchiveRoot = "${cfg.storageRoot}/.versions";
        untaggedDir = "${quarantineDir}/untagged";
        approvedDir = "${quarantineDir}/approved";
        setsDir = "${cfg.storageRoot}/sets";
      };

      beetsRunnerInstances = {

        inbox = {
          runnerKind = "import";
          description = "Beets automated inbox import worker";
          targetPath = mediaPaths.inboxDir;
          configSource = config.services.beets.renderedConfigFiles.standard;
          dataDir = "${cfg.dataRoot}/beets";
          writePaths = [
            "${cfg.dataRoot}/beets"
            mediaPaths.inboxDir
            mediaPaths.libraryDir
            mediaPaths.quarantineDir
            mediaPaths.untaggedDir
            mediaPaths.approvedDir
            # The runner's ExecStartPost clears the ready flag, so its state directory must be writable here.
            (dirOf config.services.musicIngest.readyFlag)
          ];
          mountFor = [
            "${cfg.dataRoot}/beets"
            cfg.storageRoot
            mediaPaths.inboxDir
            mediaPaths.libraryDir
            mediaPaths.untaggedDir
            mediaPaths.approvedDir
          ];
          conditionDir = mediaPaths.inboxDir;
        };

        quarantine-interactive = {
          runnerKind = "quarantine-interactive";
          description = "Beets interactive quarantine review worker";
          targetPath = mediaPaths.untaggedDir;
          configSource = config.services.beets.renderedConfigFiles.quarantine;
          dataDir = "${cfg.dataRoot}/beets";
          enableHardening = false;
          writePaths = [
            "${cfg.dataRoot}/beets"
            mediaPaths.quarantineDir
            mediaPaths.untaggedDir
          ];
          mountFor = [
            "${cfg.dataRoot}/beets"
            cfg.storageRoot
            mediaPaths.quarantineDir
            mediaPaths.untaggedDir
          ];
          conditionDir = mediaPaths.quarantineDir;
        };

        reconcile = {
          runnerKind = "reconcile";
          description = "Beets library reconciliation worker";
          targetPath = mediaPaths.libraryDir;
          configSource = config.services.beets.renderedConfigFiles.standard;
          dataDir = "${cfg.dataRoot}/beets";
          writePaths = [
            "${cfg.dataRoot}/beets"
            mediaPaths.libraryDir
          ];
          mountFor = [
            "${cfg.dataRoot}/beets"
            cfg.storageRoot
            mediaPaths.libraryDir
          ];
          conditionDir = mediaPaths.libraryDir;
        };

        duplicates = {
          runnerKind = "duplicates";
          description = "Beets duplicate detection and cleanup (interactive)";
          targetPath = mediaPaths.libraryDir;
          configSource = config.services.beets.renderedConfigFiles.standard;
          dataDir = "${cfg.dataRoot}/beets";
          writePaths = [
            mediaPaths.libraryDir
          ];
          mountFor = [
            cfg.storageRoot
            mediaPaths.libraryDir
          ];
          conditionDir = mediaPaths.libraryDir;
        };
      };

    in
    {
      imports = [ ../backups/state-backups/_consumer.nix ];

      options.applications.music = {
        dataRoot = lib.mkOption {
          type = lib.types.str;
          description = "Top-level data root for music application service state. Host-required: no fleet-wide default.";
        };

        storageRoot = lib.mkOption {
          type = lib.types.str;
          description = ''
            Root of the music storage subtree. Host-required: no fleet-wide default.
            The conventional subtree (library/, playlists/, inbox/, quarantine/,
            .versions/) is derived internally from this root and is not overridable;
            only the root itself is a host binding.
          '';
        };

        syncthingDevices = lib.mkOption {
          type = lib.types.attrsOf lib.types.attrs;
          default = {
            arch = {
              id = "L43OT2A-IULZ4LG-YRFMARJ-EX2CDF3-ZYTXGEX-UGWAYE6-K46I3BA-3KZF2AE";
            };
            windows = {
              id = "XDJJL7S-JM2SOTY-XFAMJ36-DJPKKPP-SEYNXXO-CDKRXUR-HF6XCEZ-44U4CQR";
            };
            home-forge = {
              id = "MBPDSQR-VPJRSY7-MUP2YDM-MDVRFMQ-UMQTZCQ-GZBUQW6-LE65KVE-S2SCKAB";
            };
          };
          description = "Syncthing device map for this application composition.";
        };

        syncthingFolders = lib.mkOption {
          type = lib.types.attrsOf lib.types.attrs;
          default = {
            library = {
              path = mediaPaths.libraryDir;
              type = "sendreceive";
              versioning = {
                type = "staggered";
                params = {
                  fsPath = "${mediaPaths.versionArchiveRoot}/library";
                };
              };
              ignorePerms = true;
              ensureDir = true;
              ensureMarker = true;
              ensureAcl = true;
              devices = [
                "arch"
                "windows"
                "home-forge"
              ];
            };
            quarantine = {
              path = mediaPaths.quarantineDir;
              type = "sendreceive";
              versioning = {
                type = "staggered";
                params = {
                  fsPath = "${mediaPaths.versionArchiveRoot}/quarantine";
                };
              };
              ignorePerms = true;
              ensureDir = true;
              ensureMarker = true;
              ensureAcl = true;
              devices = [
                "arch"
                "windows"
              ];
            };
            inbox = {
              path = mediaPaths.inboxDir;
              type = "sendreceive";
              versioning = {
                type = "staggered";
                params = {
                  fsPath = "${mediaPaths.versionArchiveRoot}/inbox";
                };
              };
              ignorePerms = true;
              ensureDir = true;
              ensureMarker = true;
              ensureAcl = true;
              devices = [
                "arch"
                "windows"
                "home-forge"
              ];
            };
          };
          description = "Syncthing folder map for this application composition.";
        };

        audiomuse = {
          enable = lib.mkEnableOption "AudioMuseAI Navidrome similarity extension" // {
            default = false;
            description = "Enable AudioMuseAI as an optional Navidrome similarity extension. When enabled, composes the AudioMuse core service and Navidrome plugin wiring.";
          };

          postgresHost = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "PostgreSQL hostname for AudioMuse; null uses the leaf default.";
          };

          postgresPort = lib.mkOption {
            type = lib.types.nullOr lib.types.port;
            default = null;
            description = "PostgreSQL TCP port for AudioMuse; null uses the leaf default.";
          };
        };

        navidrome.enable = lib.mkEnableOption "Navidrome within the music application" // {
          default = true;
          description = "Whether the music application composes the Navidrome leaf service and its state-backup contract.";
        };

        secretFiles.host = secretHelpers.mkSecretFileOption "music-host-secrets";

        slskdDomain = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Public domain for the slskd web UI vhost; null composes no vhost.";
        };

        configFiles = lib.mkOption {
          type = lib.types.submodule {
            options = {
              standard = lib.mkOption {
                type = lib.types.path;
                default = ./beets/files/beets-config.yaml;
              };
              quarantine = lib.mkOption {
                type = lib.types.path;
                default = ./beets/files/beets-quarantine-config.yaml;
              };
            };
          };
          default = { };
        };

        # Read-only contract for DJ: typed, unset on hosts that do not select music, and assigned only while enabled.
        contract = lib.mkOption {
          type = lib.types.submodule {
            options = {
              storageRoot = lib.mkOption { type = lib.types.str; };
              libraryDir = lib.mkOption { type = lib.types.str; };
              playlistsDir = lib.mkOption { type = lib.types.str; };
            };
          };
          readOnly = true;
          description = "Read-only music storage/library contract consumed by the DJ aspect.";
        };
      };

      config = lib.mkMerge [
        {
          applications.music.contract = {
            inherit (cfg) storageRoot;
            inherit (mediaPaths) libraryDir;
            inherit (mediaPaths) playlistsDir;
          };

          assertions = [
            {
              assertion = !cfg.audiomuse.enable || localPostgres != null || cfg.audiomuse.postgresHost != null;
              message = "applications.music.audiomuse is enabled but no PostgreSQL endpoint is available: run the cluster on this host (select the postgres aspect) or set applications.music.audiomuse.postgresHost for a database that lives elsewhere.";
            }
          ];

          # Storage ownership lives in music-storage; only explicit paths are injected here.
          services.musicStorage = {
            enable = true;
            inherit (cfg) storageRoot;
            inherit (mediaPaths) libraryDir;
            inherit (mediaPaths) playlistsDir;
            inherit (mediaPaths) inboxDir;
            inherit (mediaPaths) quarantineDir;
            inherit (mediaPaths) versionArchiveRoot;
          };

          users.users.dev.extraGroups = lib.mkAfter [
            "beets"
            "music-ingest"
            "media"
          ];

          services.syncthing = {
            enable = true;
            dataDir = "${cfg.dataRoot}/syncthing";
            configDir = "${cfg.dataRoot}/syncthing/config";
            deviceTargets = cfg.syncthingDevices;
            folderTargets = lib.mapAttrs (
              _name: folder:
              folder
              // {
                ensureDir = false;
              }
            ) cfg.syncthingFolders;
          };

          services.state-backups.services.syncthing = {
            enable = true;
            mode = "live";
            paths = [ "${cfg.dataRoot}/syncthing" ];
          };

          services.navidrome = {
            enable = cfg.navidrome.enable;
            inherit (mediaPaths) libraryDir;
            inherit (mediaPaths) quarantineDir;
            extraDirs = [ mediaPaths.setsDir ];
            dataDir = "${cfg.dataRoot}/navidrome";
            audiomuse.enable = cfg.audiomuse.enable;
          };

          services.state-backups.services.navidrome = {
            enable = cfg.navidrome.enable;
            mode = "live";
            paths = [ "${cfg.dataRoot}/navidrome" ];
          };

          services.audiomuse = lib.mkIf cfg.audiomuse.enable {
            enable = true;
            dataDir = "${cfg.dataRoot}/audiomuse";
            timeZone = config.time.timeZone;
            secretFiles.host = cfg.secretFiles.host;
            secretFiles.db = lib.mkDefault cfg.secretFiles.host;
            postgresHost =
              if cfg.audiomuse.postgresHost != null then cfg.audiomuse.postgresHost else audiomusePostgres.host;
            postgresPort =
              if cfg.audiomuse.postgresPort != null then cfg.audiomuse.postgresPort else audiomusePostgres.port;
          };

          services.beets = {
            dataDir = "${cfg.dataRoot}/beets";
            inherit (mediaPaths) inboxDir;
            inherit (mediaPaths) libraryDir;
            inherit (mediaPaths) quarantineDir;
            secretFiles.host = cfg.secretFiles.host;
            configFiles = {
              standard = cfg.configFiles.standard;
              quarantine = cfg.configFiles.quarantine;
            };
            runners = beetsRunnerInstances;
            notify = {
              enable = true;
              # nix-fleet severity vocabulary; the music topic travels in the CLI call.
              tier = "failure";
            };
          };

          services.state-backups.services.beets = {
            enable = true;
            mode = "live";
            paths = [ "${cfg.dataRoot}/beets" ];
          };

          # Automated runners only, failure-only: oneshot success is not an operator event. A renamed runner fails the contract.
          services.notify.events =
            lib.genAttrs
              [
                "beets-inbox"
                "beets-reconcile"
                "beets-duplicates"
              ]
              (_: {
                failure = { };
              });

          # Ingest is owned by music-ingest; this composition injects explicit paths only.
          services.musicIngest = {
            enable = true;
            inherit (mediaPaths) inboxDir;
            inherit (cfg) storageRoot;
            onSuccessUnit = "beets-inbox.service";
          };

          services.beets.onSuccessUnits = [
            "media-permission-reconcile.service"
          ]
          ++ lib.optional cfg.navidrome.enable "navidrome-scan.service";

          # Touched by preprocess when an import is due; beets-inbox gates on it.
          services.beets.importReadyFlag = config.services.musicIngest.readyFlag;

          programs.zsh.shellAliases = {
            b = "sudo -u beets env BEETSDIR=${config.services.beets.dataDir} HOME=${config.services.beets.dataDir} beet -c ${config.services.beets.renderedConfigFiles.quarantine}";
          };

          services.state-backups.services.media = {
            enable = true;
            mode = "live";
            paths = [ cfg.storageRoot ];
            # Syncthing-internal; the engine-dj quiesce hooks stop the VM first.
            exclude = [ mediaPaths.versionArchiveRoot ];
          };

          services.slskd = {
            downloadsPath = "${mediaPaths.inboxDir}/slskd";
            incompletePath = "${mediaPaths.inboxDir}/slskd-incomplete";
            shareDirectories = [ mediaPaths.libraryDir ];
            secretFiles.host = cfg.secretFiles.host;
            downloadCompleteScript = config.services.musicIngest.downloadCompleteScript;
          };

          services.slskd.domain = lib.mkIf (cfg.slskdDomain != null) cfg.slskdDomain;

          services.tagr = {
            enable = true;
            dataDir = "${cfg.dataRoot}/tagr";
            libraryPath = mediaPaths.libraryDir;
            quarantinePath = mediaPaths.quarantineDir;
            secretFiles.host = cfg.secretFiles.host;
          };
        }
      ];
    };
}
