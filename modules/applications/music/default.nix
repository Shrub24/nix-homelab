{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.applications.music;
  globals = import ../../../policy/globals.nix;
  secretHelpers = import ../../../lib/secrets.nix { inherit lib; };

  # Concrete media paths derived at the application layer.
  mediaPaths = rec {
    inherit (cfg) inboxDir libraryDir quarantineDir;
    untaggedDir = "${quarantineDir}/untagged";
    approvedDir = "${quarantineDir}/approved";
  };

  # Beets config files live under the music/ subdirectory (sibling to this file).
  beetsConfigDir = ./files;
  beetsConfigs = {
    standard = "${beetsConfigDir}/beets-config.yaml";
    quarantine = "${beetsConfigDir}/beets-quarantine-config.yaml";
  };

  # Sops-rendered config paths (secrets substituted). Falls back to raw template
  # when sops templates are not configured.
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

  # ffmpeg pre-processing binary for lossless-to-AIFF conversion (pre-import).
  ffmpegPreprocessBin = pkgs.writeShellApplication {
    name = "ffmpeg-preprocess";
    runtimeInputs = [
      pkgs.ffmpeg
      pkgs.findutils
      pkgs.coreutils
    ];
    text = builtins.readFile ./files/ffmpeg-preprocess.sh;
  };

  # Interactive wrapper for manual quarantine import.
  # Runs the quarantine-interactive runner as the beets user with the correct env.
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
        systemctl start navidrome-scan.service
      fi

      exit $RC
    '';
  };

  # Permission reconciliation wrapper — triggers the standalone systemd service.
  mediaFixPermsBin = pkgs.writeShellApplication {
    name = "media-fixperms";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      set -euo pipefail
      systemctl start media-permission-reconcile.service
    '';
  };

  # Duplicates detection wrapper — runs as beets user with correct env.
  # Pass any beet duplicates flags: beets-dupes --merge, beets-dupes --delete, etc.
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

  # Debounced slskd download-complete hook.
  # slskd calls this per DownloadDirectoryComplete event (runs as slskd user).
  # Uses a lockfile and 30s settle window so rapid successive album completions
  # coalesce into a single trigger. Touches a marker file in /tmp/ that the
  # slskd-download-trigger.path unit watches to start ffmpeg-preprocess.
  slskdDownloadCompleteHook = pkgs.writeShellScript "slskd-download-complete" ''
    export PATH="/run/current-system/sw/bin:$PATH"
    lockfile="/tmp/slskd-beets-debounce.lock"
    trigger="/tmp/slskd-download-trigger"

    # If the import pipeline is currently running, skip — it will pick up new files.
    if systemctl is-active --quiet beets-inbox.service || \
       systemctl is-active --quiet ffmpeg-preprocess.service; then
      exit 0
    fi

    (
      # If another debounce is already sleeping, let it handle it.
      if ! mkdir "$lockfile" 2>/dev/null; then
        exit 0
      fi
      trap 'rmdir "$lockfile" 2>/dev/null' EXIT

      # Wait for all concurrent downloads to settle.
      while true; do
        sleep 30
        # Re-check: if pipeline started while we slept, done.
        if systemctl is-active --quiet beets-inbox.service || \
           systemctl is-active --quiet ffmpeg-preprocess.service; then
          exit 0
        fi
        # If no more recent download events happened, fire.
        if [ ! -f "$lockfile/.trigger" ]; then
          break
        fi
        rm -f "$lockfile/.trigger"
      done

      touch "$trigger"
    ) &
  '';

  # SOPS secret entries for Beets plugin credentials.
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
    content = builtins.replaceStrings (map (e: e.placeholder) beetsSecretEntries) (map (
      e: config.sops.placeholder.${e.secretName}
    ) beetsSecretEntries) (builtins.readFile beetsConfigs.${name});
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

  # ------------------------------------------------------------------------ #
  # Concrete runner instances for this music application
  # ------------------------------------------------------------------------ #
  # Each instance is typed and grounded to application-owned paths and configs.
  # Built-in runner kinds only; no arbitrary custom commands.

  beetsRunnerInstances = {

    inbox = {
      runnerKind = "import";
      description = "Beets automated inbox import worker";
      targetPath = mediaPaths.inboxDir;
      configSource = beetsRenderedConfigs.standard;
      mediaRoot = cfg.mediaRoot;
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
        cfg.mediaRoot
        mediaPaths.inboxDir
        mediaPaths.libraryDir
        mediaPaths.untaggedDir
        mediaPaths.approvedDir
      ];
      conditionDir = mediaPaths.inboxDir;
      # Timer purposefully disabled — rely on event-driven triggers only
      # (slskdN hook → PathChanged, dropbox → PathModified).
      # triggers.timer = {
      #   OnBootSec = "5m";
      #   OnUnitActiveSec = "15m";
      #   RandomizedDelaySec = "2m";
      # };

    };

    quarantine-interactive = {
      runnerKind = "quarantine-interactive";
      description = "Beets interactive quarantine review worker";
      targetPath = mediaPaths.untaggedDir;
      configSource = beetsRenderedConfigs.quarantine;
      mediaRoot = cfg.mediaRoot;
      dataDir = "${cfg.dataRoot}/beets";
      enableHardening = false;
      writePaths = [
        "${cfg.dataRoot}/beets"
        mediaPaths.quarantineDir
        mediaPaths.untaggedDir
      ];
      mountFor = [
        "${cfg.dataRoot}/beets"
        cfg.mediaRoot
        mediaPaths.quarantineDir
        mediaPaths.untaggedDir
      ];
      conditionDir = mediaPaths.quarantineDir;
      # No timer - operator-invoked only over SSH TTY.
    };

    reconcile = {
      runnerKind = "reconcile";
      description = "Beets library reconciliation worker";
      targetPath = mediaPaths.libraryDir;
      configSource = beetsRenderedConfigs.standard;
      mediaRoot = cfg.mediaRoot;
      dataDir = "${cfg.dataRoot}/beets";
      writePaths = [
        "${cfg.dataRoot}/beets"
        mediaPaths.libraryDir
      ];
      mountFor = [
        "${cfg.dataRoot}/beets"
        cfg.mediaRoot
        mediaPaths.libraryDir
      ];
      conditionDir = mediaPaths.libraryDir;
      # No timer - operator-invoked for maintenance.
    };

    duplicates = {
      runnerKind = "duplicates";
      description = "Beets duplicate detection and cleanup (interactive)";
      targetPath = mediaPaths.libraryDir;
      configSource = beetsRenderedConfigs.standard;
      mediaRoot = cfg.mediaRoot;
      dataDir = "${cfg.dataRoot}/beets";
      writePaths = [
        mediaPaths.libraryDir
      ];
      mountFor = [
        cfg.mediaRoot
        mediaPaths.libraryDir
      ];
      conditionDir = mediaPaths.libraryDir;
      # No timer - operator-invoked for manual review.
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
    ../../services/music/soulsync.nix
    ../../services/music/tagr.nix
  ];

  options.applications.music = {
    enable = lib.mkEnableOption "music application composition";

    dataRoot = lib.mkOption {
      type = lib.types.str;
      default = globals.applications.music.dataRoot;
      description = "Top-level data root for music application services.";
    };

    mediaRoot = lib.mkOption {
      type = lib.types.str;
      default = globals.applications.music.mediaRoot;
      description = "Top-level media root for music application services.";
    };

    inboxDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.mediaRoot}/inbox";
      description = "Shared inbox directory composed at the application layer.";
    };

    libraryDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.mediaRoot}/library";
      description = "Shared library directory composed at the application layer.";
    };

    quarantineDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.mediaRoot}/quarantine";
      description = "Shared quarantine directory composed at the application layer.";
    };

    versionArchiveRoot = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.mediaRoot}/.versions";
      description = "Media-local root for Syncthing version archives kept outside scanned music trees.";
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
      };
      description = "Syncthing device map for this application composition.";
    };

    syncthingFolders = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = {
        library = {
          path = cfg.libraryDir;
          type = "sendreceive";
          versioning = {
            type = "staggered";
            params = {
              fsPath = "${cfg.versionArchiveRoot}/library";
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
        quarantine = {
          path = cfg.quarantineDir;
          type = "sendreceive";
          versioning = {
            type = "staggered";
            params = {
              fsPath = "${cfg.versionArchiveRoot}/quarantine";
            };
          };
          ignorePerms = true;
          ensureDir = true;
          ensureMarker = true;
          ensureAcl = true;
          devices = [ "arch" ];
        };
      };
      description = "Syncthing folder map for this application composition.";
    };

    audiomuse = {
      enable = lib.mkEnableOption "AudioMuseAI Navidrome similarity extension" // {
        default = false;
        description = "Enable AudioMuseAI as an optional Navidrome similarity extension. When enabled, composes the AudioMuse core service and Navidrome plugin wiring.";
      };
    };

    secretFiles.host = secretHelpers.mkSecretFileOption "music-host-secrets";
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
      libraryDir = cfg.libraryDir;
      quarantineDir = cfg.quarantineDir;
      dataDir = "${cfg.dataRoot}/navidrome";
      audiomuse.enable = cfg.audiomuse.enable;
    };

    services.state-backups.services.navidrome = {
      enable = true;
      mode = "live";
      paths = [ "${cfg.dataRoot}/navidrome" ];
    };

    services.audiomuse = lib.mkIf cfg.audiomuse.enable {
      enable = true;
      dataDir = "${cfg.dataRoot}/audiomuse";
      timeZone = config.time.timeZone;
      secretFiles.host = cfg.secretFiles.host;
    };

    services.beets = {
      dataDir = "${cfg.dataRoot}/beets";
      mediaRoot = cfg.mediaRoot;
      inboxDir = cfg.inboxDir;
      libraryDir = cfg.libraryDir;
      quarantineDir = cfg.quarantineDir;
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
      unitConfig.RequiresMountsFor = [ cfg.mediaRoot ];
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
                fixup "${mediaPaths.quarantineDir}"
                fixup "${mediaPaths.untaggedDir}"
                fixup "${mediaPaths.approvedDir}"
              '';
            };
          in
          "${fixupScript}/bin/media-permission-reconcile";
      };
    };

    services.beets.onSuccessUnits = [
      "media-permission-reconcile.service"
      "navidrome-scan.service"
    ];

    # ---------------------------------------------------------------------- #
    # ffmpeg-preprocess: pre-import lossless → AIFF conversion
    #
    # Event-driven trigger architecture:
    #
    #   dropbox/ dir     → PathModified (flat dirs from Syncthing/manual)
    #   slskd downloads  → DownloadDirectoryComplete hook (native slskd event)
    #
    # Both converge on ffmpeg-preprocess.service → beets-inbox.service.
    # ---------------------------------------------------------------------- #
    systemd.services.ffmpeg-preprocess = {
      description = "Pre-process incoming lossless audio to AIFF before import";
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

    # Dropbox: flat manual/Syncthing drops — PathModified on flat dir.
    systemd.paths.dropbox-inbox = {
      enable = true;
      wantedBy = [ "multi-user.target" ];
      unitConfig = {
        RequiresMountsFor = cfg.mediaRoot;
        Unit = "ffmpeg-preprocess.service";
      };
      pathConfig = {
        PathModified = "${cfg.inboxDir}/dropbox";
      };
    };

    # slskd downloads: native hook touches trigger file after debounce.
    systemd.paths.slskd-download-trigger = {
      enable = true;
      wantedBy = [ "multi-user.target" ];
      unitConfig = {
        RequiresMountsFor = cfg.mediaRoot;
        Unit = "ffmpeg-preprocess.service";
      };
      pathConfig = {
        PathChanged = "/tmp/slskd-download-trigger";
      };
    };

    environment.systemPackages = [
      ffmpegPreprocessBin
      beetsInteractiveBin
      beetsDupesBin
      mediaFixPermsBin
    ];

    services.state-backups.services.media = {
      enable = true;
      mode = "live";
      paths = [ cfg.mediaRoot ];
      exclude = [
        cfg.versionArchiveRoot
      ];
    };

    services.slskd = {
      downloadsPath = "${cfg.mediaRoot}/inbox/slskd";
      incompletePath = "${cfg.mediaRoot}/slskd-incomplete";
      domain = "oci-melb-1";
      secretFiles.host = cfg.secretFiles.host;
      downloadCompleteScript = slskdDownloadCompleteHook;
    };

    services.soulsync = {
      enable = false;
      dataDir = "${cfg.dataRoot}/soulsync";
      mediaRoot = cfg.mediaRoot;
      downloadPath = "${cfg.mediaRoot}/inbox/slskd";
      transferPath = cfg.libraryDir;
      stagingPath = "${cfg.quarantineDir}/approved";
      unresolvedPath = "${cfg.quarantineDir}/untagged";
      timeZone = config.time.timeZone;
      secretFiles.host = cfg.secretFiles.host;
      conservativeDefaults = {
        metadataFallbackSource = "discogs";
        disableBroadRepairJobs = true;
        controlPlaneOnly = true;
      };
    };

    services.state-backups.services.soulsync = lib.mkIf config.services.soulsync.enable {
      enable = true;
      mode = "live";
      paths = [ "${cfg.dataRoot}/soulsync" ];
    };

    services.tagr = {
      enable = true;
      dataDir = "${cfg.dataRoot}/tagr";
      mediaRoot = cfg.mediaRoot;
      secretFiles.host = cfg.secretFiles.host;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.mediaRoot} 0755 root root - -"
      "z ${cfg.mediaRoot} 0755 root root - -"
      "d ${cfg.versionArchiveRoot} 2775 root media - -"
      "d ${cfg.versionArchiveRoot}/library 2775 root media - -"
      "a+ ${cfg.versionArchiveRoot}/library - - - - user:syncthing:rwx"
      "a+ ${cfg.versionArchiveRoot}/library - - - - default:user:syncthing:rwX"
      "d ${cfg.versionArchiveRoot}/quarantine 2775 root media - -"
      "a+ ${cfg.versionArchiveRoot}/quarantine - - - - user:syncthing:rwx"
      "a+ ${cfg.versionArchiveRoot}/quarantine - - - - default:user:syncthing:rwX"
      "d ${cfg.libraryDir} 2775 root music-ingest - -"
      "a+ ${cfg.libraryDir} - - - - group:music-ingest:rwX"
      "a+ ${cfg.libraryDir} - - - - default:group:music-ingest:rwX"
      "a+ ${cfg.libraryDir} - - - - group:media:r-X"
      "a+ ${cfg.libraryDir} - - - - default:group:media:r-X"
      "d ${cfg.quarantineDir} 2775 root music-ingest - -"
      "a+ ${cfg.quarantineDir} - - - - group:music-ingest:rwX"
      "a+ ${cfg.quarantineDir} - - - - default:group:music-ingest:rwX"
      "a+ ${cfg.quarantineDir} - - - - group:media:r-X"
      "a+ ${cfg.quarantineDir} - - - - default:group:media:r-X"
      "d ${cfg.inboxDir} 2775 root music-ingest - -"
      "z ${cfg.inboxDir} 2775 root music-ingest - -"
      "d ${cfg.inboxDir}/dropbox 2775 root music-ingest - -"
      "a+ ${cfg.inboxDir} - - - - group:music-ingest:rwX"
      "a+ ${cfg.inboxDir} - - - - default:group:music-ingest:rwX"
      "a+ ${cfg.inboxDir} - - - - group:media:r-X"
      "a+ ${cfg.inboxDir} - - - - default:group:media:r-X"
      "f /var/lib/slskd/environment 0640 slskd slskd - -"
      "f /var/lib/tagr/environment 0640 root root - -"
    ];
  };
}
