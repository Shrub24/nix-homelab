{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  cfg = config.services.beets;
  secretHelpers = import ../../../lib/secrets.nix { inherit lib; };
  notifyPkg = self.packages.${pkgs.stdenv.hostPlatform.system}.notify;

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

  mediaPaths = rec {
    inboxDir = if cfg.inboxDir != null then cfg.inboxDir else "${cfg.mediaRoot}/inbox";
    libraryDir = if cfg.libraryDir != null then cfg.libraryDir else "${cfg.mediaRoot}/library";
    quarantineDir =
      if cfg.quarantineDir != null then cfg.quarantineDir else "${cfg.mediaRoot}/quarantine";
    untaggedDir = "${quarantineDir}/untagged";
    approvedDir = "${quarantineDir}/approved";
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

  runnerKinds = import ./runners.nix {
    inherit pkgs lib;
    beets = beetsRuntime;
    notify = notifyPkg;
    mediaPaths = mediaPaths;
    dataDir = cfg.dataDir;
  };

  aclForDir = dir: [
    "a+ ${dir} - - - - group:music-ingest:rwx"
    "a+ ${dir} - - - - default:group:music-ingest:rwX"
    "a+ ${dir} - - - - group:media:r-X"
    "a+ ${dir} - - - - default:group:media:r-X"
  ];

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
      description = runnerInstance.description;
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

  permissionReconcileBin = runnerKinds.permission-reconcile;

in
{
  options.services.beets = {
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/srv/data/beets";
      description = "Data directory for beets runtime.";
    };

    mediaRoot = lib.mkOption {
      type = lib.types.str;
      default = "/srv/media";
      description = "Root directory for media paths.";
    };

    inboxDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional full path for inbox directory (defaults to mediaRoot + /inbox).";
    };

    libraryDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional full path for library directory (defaults to mediaRoot + /library).";
    };

    quarantineDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional full path for quarantine root (always creates fixed untagged/approved subdirs).";
    };

    secretFiles.host = secretHelpers.mkSecretFileOption "beets-host-secrets";

    notify = lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Send apprise notification on runner failure.";
          };
          tier = lib.mkOption {
            type = lib.types.str;
            default = "warning";
            description = "Notification tier to use (references services.apprise.telegram.chatIds).";
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
                "permission-reconcile"
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
            mediaRoot = lib.mkOption {
              type = lib.types.str;
              description = "Media root path.";
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
  };

  config = lib.mkIf (cfg.secretFiles.host != null) {
    assertions = [
      (secretHelpers.mkRequiredSecretAssertion {
        enable = cfg.secretFiles.host != null;
        file = cfg.secretFiles.host;
        feature = "services.beets";
        label = "secretFiles.host";
      })
    ];

    users.groups.beets = { };
    users.users.beets = {
      isSystemUser = true;
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
    ]
    ++ builtins.map (r: runnerKinds.${r.runnerKind}) (builtins.attrValues cfg.runners);

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 beets beets - -"
      "d ${cfg.dataDir}/state 0750 beets beets - -"
      "d ${cfg.dataDir}/logs 0750 beets beets - -"
      "a+ ${cfg.dataDir}/logs - - - - user:dev:r-x"
      "a+ ${cfg.dataDir}/logs - - - - default:user:dev:r-x"
      "d ${mediaPaths.untaggedDir} 2775 root music-ingest - -"
      "d ${mediaPaths.approvedDir} 2775 root music-ingest - -"
    ]
    ++ aclForDir mediaPaths.untaggedDir
    ++ aclForDir mediaPaths.approvedDir;

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
          // lib.optionalAttrs (onFailureUnits != [ ] || kind == "import") {
            unitConfig =
              (baseUnit.unitConfig or { })
              // lib.optionalAttrs (onFailureUnits != [ ]) {
                OnFailure = lib.concatStringsSep " " onFailureUnits;
              }
              // lib.optionalAttrs (kind == "import") {
                StartLimitBurst = "3";
                StartLimitIntervalSec = "1800";
              };
          }
          // {
            serviceConfig = (baseUnit.serviceConfig or { }) // {
              ExecStartPost = [ "+${permissionReconcileBin}/bin/beets-runner-permission-reconcile" ];
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
      (lib.mapAttrs'
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
      )
      // (lib.mapAttrs' (
        runnerName: _runner:
        lib.nameValuePair "beets-${runnerName}-retry" {
          enable = true;
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnActiveSec = "10min";
            Unit = "beets-${runnerName}.service";
          };
        }
      ) (lib.filterAttrs (_: r: r.runnerKind == "import") cfg.runners));

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
  };
}
