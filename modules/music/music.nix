# Music deployment aspect (dendritic Stage 6, D-052). Published from this
# discovered contributor; selected only on home-forge. Selecting the aspect is
# its top-level enablement (applications.music.enable = true, S6-2), and the
# aspect owns composition only: shared path derivation, feature choices,
# service/backup wiring, secret-file passthrough, success-chain intent, the
# dev/zsh operator surface, and the read-only music library/storage contract.
#
# Concrete mechanisms are their own discovered aspects (audiomuse, syncthing,
# navidrome, slskd, beets, tagr, music-ingest, music-storage), composed here by
# flake-level imports of config.flake.modules.nixos.<name>. Music and DJ remain
# separately selected aspects; DJ consumes applications.music.contract through
# a read-only config edge with a named assertion (S6-3) and never imports or
# enables music.
{ ... }:
{
  flake.modules.nixos.music =
    {
      lib,
      config,
      options,
      pkgs,
      ...
    }:
    let
      cfg = config.applications.music;
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };

      # Shared-PostgreSQL endpoint for AudioMuse. A host that runs its own
      # cluster serves AudioMuse locally over the container bridge; otherwise the
      # database lives elsewhere and the internal transport contract (stage 8
      # task 4.2, HIC-4) resolves it. Forced only where used (inside the
      # audiomuse enable gate below), so a host that selects music without
      # AudioMuse never reads either. The explicit leaf options still win.
      # `options` (not `config`) is what can be probed safely: reading an
      # undeclared option path raises NixOS' "did you mean" error, so the
      # declaration is checked before the value is read.
      hasLocalCluster = lib.hasAttrByPath [ "services" "postgres" "localEndpoint" ] options;
      localPostgres = if hasLocalCluster then config.services.postgres.localEndpoint else null;
      internalPostgres = config.repo.internal.postgres.postgres;
      audiomusePostgres =
        if localPostgres != null then
          {
            host = "host.containers.internal";
            inherit (localPostgres) port;
          }
        else
          internalPostgres;

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

      options.applications.music = {
        enable = lib.mkEnableOption "music application composition";

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

        # Read-only music library/storage contract (S6-3). Declared as a typed
        # submodule with no nullable/default sentinel: the composition assigns
        # its value only inside the lib.mkIf cfg.enable body below, so it has
        # no value when the selected aspect is disabled and does not exist at
        # all on hosts that never select the music aspect (this module is not
        # imported there). DJ reads it via `config.applications.music.contract
        # or null`; the value is not overridable.
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
          # Selecting the music deployment aspect is its top-level enablement (S6-2).
          applications.music.enable = true;
        }

        (lib.mkIf cfg.enable {
          # Read-only music storage/library contract value (S6-3), assigned only
          # while the application is enabled.
          applications.music.contract = {
            storageRoot = cfg.storageRoot;
            libraryDir = mediaPaths.libraryDir;
            playlistsDir = mediaPaths.playlistsDir;
          };

          assertions = [
            (secretHelpers.mkRequiredSecretAssertion {
              enable = cfg.enable;
              file = cfg.secretFiles.host;
              feature = "applications.music";
              label = "secretFiles.host";
            })
          ];

          # Storage ownership (groups, media tmpfiles/ACLs, permission reconcile)
          # lives in the private musicStorage leaf (S6-7); only explicit paths are
          # injected here.
          services.musicStorage = {
            enable = true;
            storageRoot = cfg.storageRoot;
            libraryDir = mediaPaths.libraryDir;
            playlistsDir = mediaPaths.playlistsDir;
            inboxDir = mediaPaths.inboxDir;
            quarantineDir = mediaPaths.quarantineDir;
            versionArchiveRoot = mediaPaths.versionArchiveRoot;
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
            libraryDir = mediaPaths.libraryDir;
            quarantineDir = mediaPaths.quarantineDir;
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
            inboxDir = mediaPaths.inboxDir;
            libraryDir = mediaPaths.libraryDir;
            quarantineDir = mediaPaths.quarantineDir;
            secretFiles.host = cfg.secretFiles.host;
            configFiles = {
              standard = cfg.configFiles.standard;
              quarantine = cfg.configFiles.quarantine;
            };
            runners = beetsRunnerInstances;
            notify = {
              enable = true;
              tier = "music";
            };
          };

          services.state-backups.services.beets = {
            enable = true;
            mode = "live";
            paths = [ "${cfg.dataRoot}/beets" ];
          };

          # MON-1/MON-3: the music capability owns the `beets-<runner>` units
          # instantiated from beetsRunnerInstances above, so it also owns their
          # monitoring participation; the OCI host no longer maintains a
          # reverse index of remotely placed Beets units. Only the automated
          # runners are monitored (the interactive quarantine review worker has
          # no unattended lifecycle worth reporting). A renamed runner makes
          # this contract fail closed instead of leaving a silent fragment.
          services.notification-daemon.monitor.units =
            lib.genAttrs
              [
                "beets-inbox"
                "beets-reconcile"
                "beets-duplicates"
              ]
              (_: {
                onFailure = true;
                onStart = true;
                onStop = true;
              });

          # Ingest mechanisms are owned by the private musicIngest leaf (S6-6);
          # the composition injects only explicit paths and reads back the ready
          # flag and slskd completion hook.
          services.musicIngest = {
            enable = true;
            inboxDir = mediaPaths.inboxDir;
            storageRoot = cfg.storageRoot;
            onSuccessUnit = "beets-inbox.service";
          };

          services.beets.onSuccessUnits = [
            "media-permission-reconcile.service"
          ]
          ++ lib.optional cfg.navidrome.enable "navidrome-scan.service";

          # Flag file the preprocess touches when a pass warrants an import; gates beets-inbox via ConditionPathExists.
          services.beets.importReadyFlag = config.services.musicIngest.readyFlag;

          programs.zsh.shellAliases = {
            b = "sudo -u beets env BEETSDIR=${config.services.beets.dataDir} HOME=${config.services.beets.dataDir} beet -c ${config.services.beets.renderedConfigFiles.quarantine}";
          };

          services.state-backups.services.media = {
            enable = true;
            mode = "live";
            paths = [ cfg.storageRoot ];
            # .versions are Syncthing-internal; the job's engine-dj quiesce hooks stop the VM first.
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
        })
      ];
    };
}
