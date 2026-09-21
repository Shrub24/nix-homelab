# Beets aspect contributor: composed by the music coordinator aspect by
# flake-level import; this file owns the feature body.
_: {
  flake.modules.nixos.music =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.beets;
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };
      notifyPkg = config.repo.packages.notify;

      # Shared hardened oneshot service defaults for generated beets units.
      hardenedServiceDefaults = {
        Type = "oneshot";
        UMask = "0002";
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectControlGroups = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectClock = true;
        ProtectProc = "invisible";
        RestrictSUIDSGID = true;
        RestrictRealtime = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
      };

      # Every path is injected by the caller; nothing is derived here.
      mediaPaths = rec {
        inherit (cfg) inboxDir libraryDir quarantineDir;
        untaggedDir = "${quarantineDir}/untagged";
        approvedDir = "${quarantineDir}/approved";
      };

      beetsConfigs = {
        standard = ./beets/files/beets-config.yaml;
        quarantine = ./beets/files/beets-quarantine-config.yaml;
      };

      # Composition-facing read-only interface: prefer the rendered SOPS template
      # when present, otherwise fall back to the injected source configs. Never
      # depends on cfg.runners, so the composition can build runner instances from
      # it without a cycle.
      renderedConfigFiles = {
        standard =
          if lib.hasAttrByPath [ "sops" "templates" "beets-config.yaml" "path" ] config then
            config.sops.templates."beets-config.yaml".path
          else
            cfg.configFiles.standard;
        quarantine =
          if lib.hasAttrByPath [ "sops" "templates" "beets-quarantine-config.yaml" "path" ] config then
            config.sops.templates."beets-quarantine-config.yaml".path
          else
            cfg.configFiles.quarantine;
      };

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
                "${cfg.dataDir}/state/library.db"
                "${cfg.dataDir}/convert"
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

      beets-beatport4 = pkgs.python3Packages.buildPythonPackage {
        pname = "beets-beatport4";
        version = "1.1.0";
        format = "pyproject";
        src = pkgs.python3Packages.fetchPypi {
          pname = "beets_beatport4";
          version = "1.1.0";
          hash = "sha256-JRXybbLMfZmVw3Z0+mWPi5DPSPv+MplrrfdfVfm6KvQ=";
        };
        build-system = [ pkgs.python3Packages.setuptools ];
        propagatedBuildInputs = [
          pkgs.python3Packages.requests
          pkgs.python3Packages.confuse
        ];
        # beets is provided by the pluginOverrides context at runtime;
        # skip the check that would fail during standalone build
        dontCheckRuntimeDeps = true;
      };

      beetsRuntime = pkgs.python3Packages.beets.override {
        pluginOverrides = {
          bandcamp = {
            enable = true;
            propagatedBuildInputs = [ pkgs.python3Packages.beetcamp ];
          };
          beatport4 = {
            enable = true;
            propagatedBuildInputs = [ beets-beatport4 ];
          };
        };
      };

      # Single-format checker for badfiles `commands:` (mp3 is covered by mp3val).
      # Takes the file path as $1 and exits nonzero when decoding fails.
      ffmpegCheck = pkgs.writeShellScriptBin "beet-ffmpeg-check" ''
        exec ${pkgs.ffmpeg}/bin/ffmpeg -hide_banner -v error -i "$1" -f null -
      '';

      runnerKinds = import ./_beets/runners.nix {
        inherit pkgs lib;
        beets = beetsRuntime;
        notify = notifyPkg;
        inherit mediaPaths;
        inherit (cfg) dataDir;
        inherit ffmpegCheck;
      };

      # Operator CLIs: the leaf owns the binaries generated from built-in runner
      # kinds; the composition keeps selecting runner instances and the OnSuccess
      # chain intent. beets-interactive consumes cfg.onSuccessUnits for its
      # post-success tail, preserving the exact unit set/order.
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
            -p ReadWritePaths="${cfg.dataDir} ${mediaPaths.inboxDir} ${mediaPaths.libraryDir} ${mediaPaths.quarantineDir} ${mediaPaths.untaggedDir} ${mediaPaths.approvedDir} /run/secrets/rendered" \
            -p WorkingDirectory="${cfg.dataDir}" \
            --setenv=BEETSDIR="${cfg.dataDir}" \
            --setenv=BEETS_CONFIG_SOURCE="${renderedConfigFiles.quarantine}" \
            --setenv=HOME="${cfg.dataDir}" \
            -- \
            "$RUNNER" "$TARGET"
          RC=$?
          set -e

          if [ $RC -eq 0 ]; then
            ${lib.concatMapStringsSep "\n  " (unit: "systemctl start ${unit}") cfg.onSuccessUnits}
          fi

          exit $RC
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
            -p ReadWritePaths="${cfg.dataDir} ${mediaPaths.libraryDir} /run/secrets/rendered" \
            -p WorkingDirectory="${cfg.dataDir}" \
            --setenv=BEETSDIR="${cfg.dataDir}" \
            --setenv=BEETS_CONFIG_SOURCE="${renderedConfigFiles.standard}" \
            --setenv=HOME="${cfg.dataDir}" \
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
              -p ReadWritePaths="${cfg.dataDir} ${mediaPaths.libraryDir} /run/secrets/rendered" \
              -p WorkingDirectory="${cfg.dataDir}" \
              --setenv=BEETSDIR="${cfg.dataDir}" \
              --setenv=BEETS_CONFIG_SOURCE="${renderedConfigFiles.standard}" \
              --setenv=HOME="${cfg.dataDir}" \
              -- \
              /run/current-system/sw/bin/beets-merge-splits "$@"
          fi
          export PATH="/run/current-system/sw/bin:$PATH"
        ''
        + builtins.readFile ./beets/files/merge-splits.sh;
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
              -p ReadWritePaths="${cfg.dataDir} ${mediaPaths.libraryDir} /run/secrets/rendered" \
              -p WorkingDirectory="${cfg.dataDir}" \
              --setenv=BEETSDIR="${cfg.dataDir}" \
              --setenv=BEETS_CONFIG_SOURCE="${renderedConfigFiles.standard}" \
              --setenv=HOME="${cfg.dataDir}" \
              --setenv=BEETS_PRUNE_ROOT="${mediaPaths.libraryDir}" \
              -- \
              /run/current-system/sw/bin/beets-prune-empty "$@"
          fi
          export PATH="/run/current-system/sw/bin:$PATH"
        ''
        + builtins.readFile ./beets/files/prune-empty-dirs.sh;
      };

      # Shared hardened service defaults for all generated beets units,
      # layered with beets-specific user/group/working-dir overrides.
      beetsServiceDefaults = hardenedServiceDefaults // {
        User = "beets";
        Group = "beets";
        SupplementaryGroups = [
          "music-ingest"
          "media"
        ];
        WorkingDirectory = cfg.dataDir;
        Environment = "BEETSDIR=${cfg.dataDir}";
      };

      mkBeetsService =
        runnerInstance: runnerName: kind: runnerBin:
        assert builtins.isString runnerName && runnerName != "";
        assert builtins.isString kind;
        {
          inherit (runnerInstance) description;
          unitConfig = {
            RequiresMountsFor = runnerInstance.mountFor;
            ConditionPathIsDirectory = runnerInstance.conditionDir;
          };
          after = [ "systemd-tmpfiles-setup.service" ];
          serviceConfig =
            beetsServiceDefaults
            // {
              Environment = [
                "BEETSDIR=${cfg.dataDir}"
                "BEETS_CONFIG_SOURCE=${runnerInstance.configSource}"
              ];
              ExecStart = "${runnerBin}/bin/${runnerBin.name} ${
                lib.escapeShellArgs (runnerInstance.args ++ [ runnerInstance.targetPath ])
              }";
              ReadWritePaths = runnerInstance.writePaths ++ [ "/run/secrets/rendered" ];
              ReadPaths = runnerInstance.readPaths;
            }
            // lib.optionalAttrs (runnerInstance.enableHardening != true) {
              # Allow the instance to opt out of hardening if needed.
              ProtectSystem = "full";
              ProtectHome = false;
              PrivateTmp = false;
            };
        };
    in
    {
      options.services.beets = {
        dataDir = lib.mkOption {
          type = lib.types.str;
          description = "Data directory for beets runtime. Required; injected by the caller.";
        };

        inboxDir = lib.mkOption {
          type = lib.types.str;
          description = "Inbox directory. Required; injected by the caller.";
        };

        libraryDir = lib.mkOption {
          type = lib.types.str;
          description = "Library directory. Required; injected by the caller.";
        };

        quarantineDir = lib.mkOption {
          type = lib.types.str;
          description = "Quarantine root. Required; injected by the caller. Fixed untagged/approved subdirs are derived from it.";
        };

        secretFiles.host = secretHelpers.mkSecretFileOption "beets-host-secrets";

        onSuccessUnits = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Systemd units to trigger via OnSuccess= on all beets runner services. Set from the application composition layer.";
        };

        importReadyFlag = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Flag file that must exist for import-kind runners to start (set by the application-layer preprocess when a pass warrants an import; cleared on success so failures keep it for the retry timer). Null disables the gate.";
        };

        notify = lib.mkOption {
          type = lib.types.submodule {
            options = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Send notification via the notification-daemon notify CLI on runner failure.";
              };
              tier = lib.mkOption {
                type = lib.types.str;
                default = "warning";
                description = "Notification tier to use (routed by the notification-daemon Telegram topic mapping).";
              };
            };
          };
          default = { };
          description = "Apprise/Telegram failure notification configuration for beets runners.";
        };

        # Per-runner-instance configuration, keyed by runner name.
        runners = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                runnerKind = lib.mkOption {
                  type = lib.types.enum [
                    "import"
                    "quarantine-interactive"
                    "reconcile"
                    "duplicates"
                  ];
                  description = "Built-in runner behavior.";
                };
                configSource = lib.mkOption {
                  type = lib.types.path;
                  description = "Beets YAML config path.";
                };
                targetPath = lib.mkOption {
                  type = lib.types.str;
                  description = "Target media path.";
                };
                description = lib.mkOption {
                  type = lib.types.str;
                  default = "Beets runner";
                };
                conditionDir = lib.mkOption {
                  type = lib.types.str;
                  description = "Directory that must exist before running.";
                };
                mountFor = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                };
                enableHardening = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                };
                writePaths = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                };
                readPaths = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                };
                dataDir = lib.mkOption {
                  type = lib.types.str;
                  description = "Beets runtime data dir.";
                };
                args = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                };
                preCommands = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                };
                postCommands = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                };
                triggers = lib.mkOption {
                  type = lib.types.attrsOf lib.types.attrs;
                  default = { };
                };
              };
            }
          );
          default = { };
          description = "Runner instances for this beets deployment.";
        };

        configFiles = lib.mkOption {
          type = lib.types.submodule {
            options = {
              standard = lib.mkOption { type = lib.types.path; };
              quarantine = lib.mkOption { type = lib.types.path; };
            };
          };
        };

        # Read-only composition-facing interface: renders the SOPS templates when
        # they exist, otherwise falls back to configFiles. Declared and valued
        # outside the secret-file gate so the composition can build runner
        # instances regardless of secret wiring.
        renderedConfigFiles = lib.mkOption {
          type = lib.types.submodule {
            options = {
              standard = lib.mkOption { type = lib.types.path; };
              quarantine = lib.mkOption { type = lib.types.path; };
            };
          };
          readOnly = true;
          description = "Effective Beets config paths (rendered SOPS template when present, else configFiles).";
        };
      };

      config = lib.mkMerge [
        {
          services.beets.renderedConfigFiles = renderedConfigFiles;
        }

        (lib.mkIf (cfg.secretFiles.host != null) {
          assertions = [
            (secretHelpers.mkRequiredSecretAssertion {
              enable = cfg.secretFiles.host != null;
              file = cfg.secretFiles.host;
              feature = "services.beets";
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

          # Fleet-stable identity: state moves between hosts (OCI -> home-forge), so
          # the numeric UID/GID is pinned instead of left to per-host dynamic
          # allocation (NixOS descends from 999, host-dependent).
          users.groups.beets = {
            gid = lib.mkDefault 976;
          };
          users.users.beets = {
            isSystemUser = true;
            uid = lib.mkDefault 976;
            group = "beets";
            home = cfg.dataDir;
            createHome = false;
            extraGroups = [
              "music-ingest"
              "media"
            ];
          };

          environment.systemPackages = [
            beetsRuntime
            pkgs.apprise
            pkgs.mp3val
            pkgs.ffmpeg
            ffmpegCheck
          ]
          ++ builtins.map (r: runnerKinds.${r.runnerKind}) (builtins.attrValues cfg.runners)
          ++ [
            beetsInteractiveBin
            beetsDupesBin
            beetsMergeSplitsBin
            beetsPruneEmptyBin
          ];

          systemd.tmpfiles.rules = [
            "d ${cfg.dataDir} 0750 beets beets - -"
            "d ${cfg.dataDir}/state 0750 beets beets - -"
            "d ${cfg.dataDir}/logs 0750 beets beets - -"
            "a+ ${cfg.dataDir}/logs - - - - user:dev:r-x"
            "a+ ${cfg.dataDir}/logs - - - - default:user:dev:r-x"
          ];

          # Generate one service unit per runner instance.
          systemd.services = lib.mkMerge [
            (lib.mapAttrs' (
              runnerName: runnerInstance:
              let
                kind = runnerInstance.runnerKind;
                runnerBin = runnerKinds.${kind};
                baseUnit = mkBeetsService runnerInstance runnerName kind runnerBin;
                onFailureUnits =
                  lib.optional cfg.notify.enable "beets-notify-failure@${runnerName}.service"
                  ++ lib.optional (kind == "import") "beets-${runnerName}-retry.timer";
              in
              lib.nameValuePair "beets-${runnerName}" (
                baseUnit
                // {
                  onFailure = onFailureUnits;
                  unitConfig =
                    (baseUnit.unitConfig or { })
                    // lib.optionalAttrs (kind == "import") {
                      StartLimitBurst = "3";
                      StartLimitIntervalSec = "1800";
                    }
                    // {
                      OnSuccess = cfg.onSuccessUnits;
                    }
                    // lib.optionalAttrs (kind == "import" && cfg.importReadyFlag != null) {
                      ConditionPathExists = cfg.importReadyFlag;
                    };
                  serviceConfig =
                    (baseUnit.serviceConfig or { })
                    // lib.optionalAttrs (kind == "import" && cfg.importReadyFlag != null) {
                      ExecStartPost = "-${pkgs.coreutils}/bin/rm -f ${cfg.importReadyFlag}";
                    };
                }
              )
            ) cfg.runners)

            # Failure notification template unit (oneshot, reads %i as runner unit name).
            (lib.optionalAttrs cfg.notify.enable {
              "beets-notify-failure@" = {
                description = "Beets runner failure notification for %i";
                after = [ "network.target" ];
                serviceConfig = hardenedServiceDefaults // {
                  User = "beets";
                  Group = "beets";
                  ExecStart =
                    let
                      notifyScript = pkgs.writeShellApplication {
                        name = "beets-notify-failure";
                        runtimeInputs = [
                          pkgs.systemd
                          notifyPkg
                        ];
                        text = ''
                          set -euo pipefail
                          runner="''${1:?}"
                          body="$(journalctl -u "beets-$runner.service" -n 20 --no-pager --output=short-full 2>/dev/null || echo '(no journal output)')"
                          echo "$body" | notify ${cfg.notify.tier} "Beets runner $runner failed on ${config.networking.hostName}" "failure" "music"
                        '';
                      };
                    in
                    "${notifyScript}/bin/beets-notify-failure %i";
                };
              };
            })
          ];

          # Generate timer units for runner instances that declare timer triggers.
          systemd.timers =
            lib.mapAttrs'
              (
                runnerName: runnerInstance:
                lib.nameValuePair "beets-${runnerName}-timer" {
                  enable = true;
                  timerConfig = {
                    OnBootSec = runnerInstance.triggers.timer.OnBootSec or "5m";
                    OnUnitActiveSec = runnerInstance.triggers.timer.OnUnitActiveSec or "15m";
                    RandomizedDelaySec = runnerInstance.triggers.timer.RandomizedDelaySec or null;
                    Unit = "beets-${runnerName}.service";
                    Persistent = true;
                  };
                }
              )
              (lib.filterAttrs (_: r: r ? triggers && r.triggers ? timer && r.triggers.timer != null) cfg.runners)
            // (lib.mapAttrs' (
              runnerName: runnerInstance:
              lib.nameValuePair "beets-${runnerName}-retry" {
                description = "Delayed one-shot retry for failed beets ${runnerName} run";
                timerConfig = {
                  OnActiveSec = "15min";
                  AccuracySec = "1min";
                  Persistent = true;
                  Unit = "beets-${runnerName}.service";
                };
              }
            ) (lib.filterAttrs (_: runnerInstance: runnerInstance.runnerKind == "import") cfg.runners));

          # Generate path units for runner instances that declare path triggers.
          systemd.paths =
            lib.mapAttrs'
              (
                runnerName: runnerInstance:
                lib.nameValuePair "beets-${runnerName}-path" {
                  enable = runnerInstance.triggers ? path && runnerInstance.triggers.path != null;
                  unitConfig = {
                    RequiresMountsFor = runnerInstance.mountFor;
                  };
                  pathConfig = {
                    PathModified = runnerInstance.conditionDir;
                    Unit = "beets-${runnerName}.service";
                  };
                }
              )
              (lib.filterAttrs (n: r: r ? triggers && r.triggers ? path && r.triggers.path != null) cfg.runners);
        })
      ];
    };
}
