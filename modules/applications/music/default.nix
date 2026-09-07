{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.applications.music;
  secretHelpers = import ../../../lib/secrets.nix { inherit lib; };

  mediaPaths = rec {
    libraryDir = "${cfg.storageRoot}/library";
    playlistsDir = "${cfg.storageRoot}/playlists";
    inboxDir = "${cfg.storageRoot}/inbox";
    quarantineDir = "${cfg.storageRoot}/quarantine";
    versionArchiveRoot = "${cfg.storageRoot}/.versions";
    untaggedDir = "${quarantineDir}/untagged";
    approvedDir = "${quarantineDir}/approved";
  };

  beetsConfigs = {
    standard = ./files/beets-config.yaml;
    quarantine = ./files/beets-quarantine-config.yaml;
  };

  beetsRenderedConfigs = {
    standard =
      if lib.hasAttrByPath [ "sops" "templates" "beets-config.yaml" "path" ] config then
        config.sops.templates."beets-config.yaml".path
      else
        beetsConfigs.standard;
    quarantine =
      if lib.hasAttrByPath [ "sops" "templates" "beets-quarantine-config.yaml" "path" ] config then
        config.sops.templates."beets-quarantine-config.yaml".path
      else
        beetsConfigs.quarantine;
  };

  ffmpegPreprocessBin = pkgs.writeShellApplication {
    name = "ffmpeg-preprocess";
    runtimeInputs = [
      pkgs.ffmpeg
      pkgs.findutils
      pkgs.coreutils
    ];
    text = builtins.readFile ./files/ffmpeg-preprocess.sh;
  };

  beetsInteractiveBin = pkgs.writeShellApplication {
    name = "beets-interactive";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      set -euo pipefail

      RUNNER="/run/current-system/sw/bin/beets-runner-quarantine-interactive"
      TARGET="''${1:-${mediaPaths.untaggedDir}}"
      UNIT="beets-interactive-$(date -u +"%Y%m%dT%H%M%SZ")"

      set +e
      systemd-run --pipe --wait \
        --unit="$UNIT" \
        -p User=beets \
        -p Group=beets \
        -p SupplementaryGroups="music-ingest media" \
        -p ReadWritePaths="/srv/data/beets ${mediaPaths.inboxDir} ${mediaPaths.libraryDir} ${mediaPaths.quarantineDir} ${mediaPaths.untaggedDir} ${mediaPaths.approvedDir} /run/secrets/rendered" \
        -p WorkingDirectory="${config.services.beets.dataDir}" \
        --setenv=BEETSDIR="${config.services.beets.dataDir}" \
        --setenv=BEETS_CONFIG_SOURCE="${beetsRenderedConfigs.quarantine}" \
        --setenv=HOME="${config.services.beets.dataDir}" \
        -- \
        "$RUNNER" "$TARGET"
      RC=$?
      set -e

      if [ $RC -eq 0 ]; then
        systemctl start media-permission-reconcile.service
        ${lib.optionalString cfg.navidrome.enable "systemctl start navidrome-scan.service"}
      fi

      exit $RC
    '';
  };

  mediaFixPermsBin = pkgs.writeShellApplication {
    name = "media-fixperms";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      set -euo pipefail
      systemctl start media-permission-reconcile.service
    '';
  };

  beetsDupesBin = pkgs.writeShellApplication {
    name = "beets-dupes";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      set -euo pipefail
      exec systemd-run --pipe --wait \
        -p User=beets \
        -p Group=beets \
        -p SupplementaryGroups="music-ingest media" \
        -p ReadWritePaths="/srv/data/beets ${mediaPaths.libraryDir} /run/secrets/rendered" \
        -p WorkingDirectory="${config.services.beets.dataDir}" \
        --setenv=BEETSDIR="${config.services.beets.dataDir}" \
        --setenv=BEETS_CONFIG_SOURCE="${beetsRenderedConfigs.standard}" \
        --setenv=HOME="${config.services.beets.dataDir}" \
        -- \
        /run/current-system/sw/bin/beets-runner-duplicates "$@"
    '';
  };

  beetsMergeSplitsBin = pkgs.writeShellApplication {
    name = "beets-merge-splits";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.diffutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.systemd
    ];
    text = ''
      set -euo pipefail
      if [ "$(id -un)" != beets ]; then
        exec systemd-run --pipe --wait \
          --unit="beets-merge-splits-$(date -u +"%Y%m%dT%H%M%SZ")" \
          -p User=beets \
          -p Group=beets \
          -p SupplementaryGroups="music-ingest media" \
          -p ReadWritePaths="${config.services.beets.dataDir} ${mediaPaths.libraryDir} /run/secrets/rendered" \
          -p WorkingDirectory="${config.services.beets.dataDir}" \
          --setenv=BEETSDIR="${config.services.beets.dataDir}" \
          --setenv=BEETS_CONFIG_SOURCE="${beetsRenderedConfigs.standard}" \
          --setenv=HOME="${config.services.beets.dataDir}" \
          -- \
          /run/current-system/sw/bin/beets-merge-splits "$@"
      fi
      export PATH="/run/current-system/sw/bin:$PATH"
    ''
    + builtins.readFile ./files/merge-splits.sh;
  };

  beetsPruneEmptyBin = pkgs.writeShellApplication {
    name = "beets-prune-empty";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.systemd
    ];
    text = ''
      set -euo pipefail
      if [ "$(id -un)" != beets ]; then
        exec systemd-run --pipe --wait \
          --unit="beets-prune-empty-$(date -u +"%Y%m%dT%H%M%SZ")" \
          -p User=beets \
          -p Group=beets \
          -p SupplementaryGroups="music-ingest media" \
          -p ReadWritePaths="${config.services.beets.dataDir} ${mediaPaths.libraryDir} /run/secrets/rendered" \
          -p WorkingDirectory="${config.services.beets.dataDir}" \
          --setenv=BEETSDIR="${config.services.beets.dataDir}" \
          --setenv=BEETS_CONFIG_SOURCE="${beetsRenderedConfigs.standard}" \
          --setenv=HOME="${config.services.beets.dataDir}" \
          --setenv=BEETS_PRUNE_ROOT="${mediaPaths.libraryDir}" \
          -- \
          /run/current-system/sw/bin/beets-prune-empty "$@"
      fi
      export PATH="/run/current-system/sw/bin:$PATH"
    ''
    + builtins.readFile ./files/prune-empty-dirs.sh;
  };

  slskdDownloadCompleteHook = pkgs.writeShellScript "slskd-download-complete" ''
    export PATH="/run/current-system/sw/bin:$PATH"
    exec systemctl try-restart slskd-settle.timer
  '';

  beetsSecretEntries = [
    {
      secretName = "beets_discogs_token";
      key = "beets/discogs_token";
      placeholder = "REPLACE_WITH_DISCOGS_USER_TOKEN";
    }
    {
      secretName = "beets_spotify_client_id";
      key = "beets/spotify_client_id";
      placeholder = "REPLACE_WITH_SPOTIFY_CLIENT_ID";
    }
    {
      secretName = "beets_spotify_client_secret";
      key = "beets/spotify_client_secret";
      placeholder = "REPLACE_WITH_SPOTIFY_CLIENT_SECRET";
    }
    {
      secretName = "beets_beatport_username";
      key = "beets/beatport_username";
      placeholder = "REPLACE_WITH_BEATPORT_USERNAME";
    }
    {
      secretName = "beets_beatport_password";
      key = "beets/beatport_password";
      placeholder = "REPLACE_WITH_BEATPORT_PASSWORD";
    }
  ];

  _mkBeetsSopsTemplate = name: {
    owner = "beets";
    group = "beets";
    mode = "0440";
    content =
      builtins.replaceStrings
        (
          [
            "__MUSIC_LIBRARY_DIR__"
            "__BEETS_STATE_DB__"
            "__BEETS_CONVERT_DIR__"
          ]
          ++ map (e: e.placeholder) beetsSecretEntries
        )
        (
          [
            mediaPaths.libraryDir
            "${cfg.dataRoot}/beets/state/library.db"
            "${cfg.dataRoot}/beets/convert"
          ]
          ++ map (e: config.sops.placeholder.${e.secretName}) beetsSecretEntries
        )
        (builtins.readFile beetsConfigs.${name});
  };

  _mkBeetsSopsSecret =
    { secretName, key, ... }:
    {
      sopsFile = cfg.secretFiles.host;
      inherit key;
      path = "/run/secrets/beets.${builtins.replaceStrings [ "beets_" ] [ "" ] secretName}";
      owner = "beets";
      group = "beets";
    };

  beetsRunnerInstances = {

    inbox = {
      runnerKind = "import";
      description = "Beets automated inbox import worker";
      targetPath = mediaPaths.inboxDir;
      configSource = beetsRenderedConfigs.standard;
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
      configSource = beetsRenderedConfigs.quarantine;
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
      configSource = beetsRenderedConfigs.standard;
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
      configSource = beetsRenderedConfigs.standard;
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
  imports = [
    ../../services/music/audiomuse.nix
    ../../services/music/syncthing.nix
    ../../services/music/navidrome.nix
    ../../services/music/slskd.nix
    ../../services/music/beets/default.nix
    ../../services/music/tagr.nix
  ];

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
            default = ./files/beets-config.yaml;
          };
          quarantine = lib.mkOption {
            type = lib.types.path;
            default = ./files/beets-quarantine-config.yaml;
          };
        };
      };
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (secretHelpers.mkRequiredSecretAssertion {
        enable = cfg.enable;
        file = cfg.secretFiles.host;
        feature = "applications.music";
        label = "secretFiles.host";
      })
    ];

    sops.templates = {
      "beets-config.yaml" = _mkBeetsSopsTemplate "standard";
      "beets-quarantine-config.yaml" = _mkBeetsSopsTemplate "quarantine";
    };
    sops.secrets = lib.listToAttrs (
      map (e: {
        name = e.secretName;
        value = _mkBeetsSopsSecret e;
      }) beetsSecretEntries
    );

    users.groups.music-ingest.gid = 990;
    users.groups.media.gid = 987;

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
      postgresHost = lib.mkIf (cfg.audiomuse.postgresHost != null) cfg.audiomuse.postgresHost;
      postgresPort = lib.mkIf (cfg.audiomuse.postgresPort != null) cfg.audiomuse.postgresPort;
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

    systemd.services.media-permission-reconcile = {
      description = "Reconcile ACLs and ownership on media directories";
      after = [ "local-fs.target" ];
      unitConfig.RequiresMountsFor = [ cfg.storageRoot ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart =
          let
            fixupScript = pkgs.writeShellApplication {
              name = "media-permission-reconcile";
              runtimeInputs = [
                pkgs.coreutils
                pkgs.findutils
                pkgs.acl
              ];
              text = ''
                set -euo pipefail
                fixup() { local d="$1"; [ -d "$d" ] || return 0
                  find "$d" -type d -exec chgrp music-ingest {} + -exec chmod 2775 {} +
                  find "$d" -type f -exec chgrp music-ingest {} + -exec chmod 0664 {} +
                  setfacl -R -m g:music-ingest:rwx "$d"
                  find "$d" -type d -exec setfacl -m d:g:music-ingest:rwX {} +
                  setfacl -R -m g:media:r-X "$d"
                  find "$d" -type d -exec setfacl -m d:g:media:r-X {} +
                  setfacl -R -m u:syncthing:rwx "$d"
                  find "$d" -type d -exec setfacl -m d:u:syncthing:rwX {} +
                }
                fixup "${mediaPaths.libraryDir}"
                fixup "${mediaPaths.playlistsDir}"
                fixup "${mediaPaths.quarantineDir}"
                fixup "${mediaPaths.untaggedDir}"
                fixup "${mediaPaths.approvedDir}"
                fixup "${mediaPaths.inboxDir}"
              '';
            };
          in
          "${fixupScript}/bin/media-permission-reconcile";
      };
    };

    services.beets.onSuccessUnits = [
      "media-permission-reconcile.service"
    ]
    ++ lib.optional cfg.navidrome.enable "navidrome-scan.service";

    # Flag file the preprocess touches when a pass warrants an import; gates beets-inbox via ConditionPathExists.
    services.beets.importReadyFlag = "/var/lib/beets/ffmpeg-preprocess/inbox-ready";

    systemd.services.ffmpeg-preprocess = {
      description = "Pre-process incoming audio to library formats before import";
      after = [ "network.target" ];
      unitConfig = {
        OnSuccess = "beets-inbox.service";
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
        ExecStart = "${ffmpegPreprocessBin}/bin/ffmpeg-preprocess ${mediaPaths.inboxDir}";
        Environment = [
          "PATH=/run/current-system/sw/bin"
        ];
        User = "beets";
        Group = "beets";
        StateDirectory = "beets/ffmpeg-preprocess";
        WorkingDirectory = "${mediaPaths.inboxDir}";
        ReadWritePaths = [ mediaPaths.inboxDir ];
      };
    };

    # Unit= is a [Path]-section key (pathConfig), not a [Unit] key.
    systemd.paths.dropbox-inbox = {
      enable = true;
      wantedBy = [ "multi-user.target" ];
      unitConfig.RequiresMountsFor = cfg.storageRoot;
      pathConfig = {
        PathModified = "${mediaPaths.inboxDir}/dropbox";
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

    environment.systemPackages = [
      ffmpegPreprocessBin
      beetsInteractiveBin
      beetsDupesBin
      beetsMergeSplitsBin
      beetsPruneEmptyBin
      mediaFixPermsBin
    ];

    programs.zsh.shellAliases = {
      b = "sudo -u beets env BEETSDIR=${config.services.beets.dataDir} HOME=${config.services.beets.dataDir} beet -c ${beetsRenderedConfigs.quarantine}";
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
      downloadCompleteScript = slskdDownloadCompleteHook;
    };

    services.slskd.domain = lib.mkIf (cfg.slskdDomain != null) cfg.slskdDomain;

    services.tagr = {
      enable = true;
      dataDir = "${cfg.dataRoot}/tagr";
      libraryPath = mediaPaths.libraryDir;
      quarantinePath = mediaPaths.quarantineDir;
      secretFiles.host = cfg.secretFiles.host;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.storageRoot} 0755 root root - -"
      "z ${cfg.storageRoot} 0755 root root - -"
      "d ${mediaPaths.versionArchiveRoot} 2775 root media - -"
      "d ${mediaPaths.versionArchiveRoot}/library 2775 root media - -"
      "a+ ${mediaPaths.versionArchiveRoot}/library - - - - user:syncthing:rwx"
      "a+ ${mediaPaths.versionArchiveRoot}/library - - - - default:user:syncthing:rwX"
      "d ${mediaPaths.versionArchiveRoot}/quarantine 2775 root media - -"
      "a+ ${mediaPaths.versionArchiveRoot}/quarantine - - - - user:syncthing:rwx"
      "a+ ${mediaPaths.versionArchiveRoot}/quarantine - - - - default:user:syncthing:rwX"
      "d ${mediaPaths.versionArchiveRoot}/inbox 2775 root media - -"
      "a+ ${mediaPaths.versionArchiveRoot}/inbox - - - - user:syncthing:rwx"
      "a+ ${mediaPaths.versionArchiveRoot}/inbox - - - - default:user:syncthing:rwX"
      "d ${mediaPaths.libraryDir} 2775 root music-ingest - -"
      "a+ ${mediaPaths.libraryDir} - - - - group:music-ingest:rwX"
      "a+ ${mediaPaths.libraryDir} - - - - default:group:music-ingest:rwX"
      "a+ ${mediaPaths.libraryDir} - - - - group:media:r-X"
      "a+ ${mediaPaths.libraryDir} - - - - default:group:media:r-X"
      # Playlists are a sibling of library, not a child: Navidrome reads
      # library/, so exporting under it would surface playlists as tracks.
      "d ${mediaPaths.playlistsDir} 2775 root music-ingest - -"
      "a+ ${mediaPaths.playlistsDir} - - - - group:music-ingest:rwX"
      "a+ ${mediaPaths.playlistsDir} - - - - default:group:music-ingest:rwX"
      "a+ ${mediaPaths.playlistsDir} - - - - group:media:r-X"
      "a+ ${mediaPaths.playlistsDir} - - - - default:group:media:r-X"
      "d ${mediaPaths.quarantineDir} 2775 root music-ingest - -"
      "a+ ${mediaPaths.quarantineDir} - - - - group:music-ingest:rwX"
      "a+ ${mediaPaths.quarantineDir} - - - - default:group:music-ingest:rwX"
      "a+ ${mediaPaths.quarantineDir} - - - - group:media:r-X"
      "a+ ${mediaPaths.quarantineDir} - - - - default:group:media:r-X"
      "d ${mediaPaths.inboxDir} 2775 root music-ingest - -"
      "z ${mediaPaths.inboxDir} 2775 root music-ingest - -"
      "d ${mediaPaths.inboxDir}/dropbox 2775 root music-ingest - -"
      "a+ ${mediaPaths.inboxDir} - - - - group:music-ingest:rwX"
      "a+ ${mediaPaths.inboxDir} - - - - default:group:music-ingest:rwX"
      "a+ ${mediaPaths.inboxDir} - - - - group:media:r-X"
      "a+ ${mediaPaths.inboxDir} - - - - default:group:media:r-X"
      "f /var/lib/slskd/environment 0640 slskd slskd - -"
      "f /var/lib/tagr/environment 0640 root root - -"
    ];
  };
}
