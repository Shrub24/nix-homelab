{
  lib,
  config,
  pkgs,
  ...
}:
let
  globals = import ../../policy/globals.nix;
  secretHelpers = import ../../lib/secrets.nix { inherit lib; };
  cfg = config.services.state-backups;

  enabledServices = lib.filterAttrs (_name: service: service.enable) cfg.services;
  serviceList = lib.attrValues enabledServices;

  allBackupPaths = lib.unique (
    lib.concatLists (map (service: service.paths ++ service.exportPaths) serviceList)
  );
  allExcludePaths = lib.unique (
    cfg.exclude ++ lib.concatLists (map (service: service.exclude) serviceList)
  );
  prepareCommands = lib.concatLists (map (service: service.prepareCommands) serviceList);
  cleanupCommands = lib.concatLists (map (service: service.cleanupCommands) serviceList);

  repository =
    "s3:${globals.s3.endpoint}/${cfg.bucket}"
    + lib.optionalString (cfg.repositoryPrefix != "") "/${cfg.repositoryPrefix}";

  prepareScript = ''
    set -euo pipefail
    mkdir -p ${cfg.stagingRoot}
    ${lib.concatStringsSep "\n" prepareCommands}
  '';

  cleanupScript = ''
    set -euo pipefail
    ${lib.concatStringsSep "\n" cleanupCommands}
  '';

  resticExtraArgs = lib.concatMapStringsSep " " (
    opt: "-o ${lib.escapeShellArg opt}"
  ) cfg.extraOptions;

  # Operator-invoked restic restore-staging helper. Restores exactly one
  # absolute include path from a snapshot into a fresh root-only directory
  # under /var/tmp/state-restore/ and prints ONLY the resulting destination
  # path on stdout (diagnostics go to stderr) so `stage=$(just ...)` works.
  # It reuses this module's exact repository, credentials, and backend
  # options, so the operator never reads secrets or passes arbitrary restic
  # flags. There is no destination argument: live service paths can never be
  # chosen or written here; applying staged files is a separate, documented
  # per-service step. --decode mode accepts base64-encoded arguments so the
  # just recipe can transport hostile values without remote shell parsing.
  restoreStageScript = pkgs.writeShellScriptBin "state-restore-stage" ''
    set -euo pipefail

    if [ "$#" -eq 3 ] && [ "$1" = "--decode" ]; then
      snap_b64=$2
      inc_b64=$3
      case "$snap_b64" in
        *[!A-Za-z0-9+/=]*)
          echo "state-restore-stage: snapshot base64 contains invalid characters" >&2
          exit 2
          ;;
      esac
      case "$inc_b64" in
        *[!A-Za-z0-9+/=]*)
          echo "state-restore-stage: include-path base64 contains invalid characters" >&2
          exit 2
          ;;
      esac
      snapshot=$(printf '%s' "$snap_b64" | ${pkgs.coreutils}/bin/base64 -d) || exit 2
      include_path=$(printf '%s' "$inc_b64" | ${pkgs.coreutils}/bin/base64 -d) || exit 2
    elif [ "$#" -eq 2 ]; then
      snapshot=$1
      include_path=$2
    else
      echo "usage: state-restore-stage [--decode <snapshot-b64> <include-path-b64>] <snapshot> <absolute-include-path>" >&2
      exit 2
    fi

    if [ -z "$snapshot" ]; then
      echo "state-restore-stage: snapshot must not be empty" >&2
      exit 2
    fi
    case "$snapshot" in
      -*)
        echo "state-restore-stage: snapshot must not start with '-' (option injection), got: $snapshot" >&2
        exit 2
        ;;
    esac

    case "$include_path" in
      /*) ;;
      *)
        echo "state-restore-stage: include path must be absolute, got: $include_path" >&2
        exit 2
        ;;
    esac
    case "$include_path" in
      *'/../'* | */..)
        echo "state-restore-stage: include path must not contain '..', got: $include_path" >&2
        exit 2
        ;;
    esac

    export RESTIC_REPOSITORY='${repository}'
    export RESTIC_PASSWORD_FILE='${config.sops.secrets.state_backups_restic_password.path}'
    env_file='${config.sops.templates."state-backups.env".path}'
    if [ ! -r "$env_file" ]; then
      echo "state-restore-stage: missing restic environment file: $env_file" >&2
      exit 1
    fi
    set -a
    . "$env_file"
    set +a

    # The staging parent is declared root-owned 0700 by tmpfiles; repair it
    # defensively before use in case activation has not run yet. The unique
    # child below it is created 0700 by mktemp.
    ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root /var/tmp/state-restore
    dest=$(${pkgs.coreutils}/bin/mktemp -d /var/tmp/state-restore/restore.XXXXXX)
    trap 'rc=$?; if [ "$rc" -ne 0 ]; then ${pkgs.coreutils}/bin/rm -rf -- "$dest"; fi' EXIT

    # End-of-options (`--`) before the snapshot prevents a leading-dash
    # snapshot from being parsed as a restic flag. restic restore writes its
    # status to stdout, so redirect it to stderr to keep the stdout contract.
    ${pkgs.restic}/bin/restic ${resticExtraArgs} restore --target "$dest" --include "$include_path" -- "$snapshot" 1>&2

    echo "$dest"
  '';
in
{
  options.services.state-backups = {
    enable = lib.mkEnableOption "host-scoped restic backups for mutable service state";

    backupName = lib.mkOption {
      type = lib.types.str;
      default = "state";
      description = "Restic backup job name used under services.restic.backups.";
    };

    bucket = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Dedicated object-storage bucket for this host's restic repository.";
    };

    repositoryPrefix = lib.mkOption {
      type = lib.types.str;
      default = "restic";
      description = "Optional prefix inside the host bucket used for the restic repository.";
    };

    stagingRoot = lib.mkOption {
      type = lib.types.str;
      default = "/srv/data/state-backups";
      description = "Host-local staging root for generated export artifacts captured by restic.";
    };

    restoreStagePackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "Operator-invoked restic restore-staging helper (state-restore-stage) installed by this module.";
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Global backup exclusions applied to the shared host restic job.";
    };

    timerConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {
        OnCalendar = "03:30";
        RandomizedDelaySec = "1h";
        Persistent = true;
      };
      description = "Timer configuration for the canonical restic backup job.";
    };

    pruneOpts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "--keep-daily 7"
        "--keep-weekly 5"
        "--keep-monthly 12"
      ];
      description = "Default retention policy passed to restic prune.";
    };

    checkOpts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "--read-data-subset=1/20" ];
      description = "Repository integrity-check arguments for the canonical backup job.";
    };

    extraOptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "s3.region=${globals.s3.region}"
      ]
      ++ lib.optional globals.s3.forcePathStyle "s3.bucket-lookup=path";
      description = "Additional restic backend options derived from canonical non-secret S3 policy.";
    };

    secretFile = secretHelpers.mkSecretFileOption "state-backups-host-secrets";

    secretKeys = {
      accessKeyId = lib.mkOption {
        type = lib.types.str;
        default = "backup/s3_access_key_id";
        description = "Secret key path for the backup S3 access key ID inside the host secret file.";
      };

      secretAccessKey = lib.mkOption {
        type = lib.types.str;
        default = "backup/s3_secret_access_key";
        description = "Secret key path for the backup S3 secret access key inside the host secret file.";
      };

      resticPassword = lib.mkOption {
        type = lib.types.str;
        default = "backup/restic_password";
        description = "Secret key path for the restic repository password inside the host secret file.";
      };
    };

    services = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Whether ${name} contributes paths or hooks to the host backup job.";
              };

              mode = lib.mkOption {
                type = lib.types.enum [
                  "export"
                  "quiesce"
                  "live"
                ];
                default = "live";
                description = "Consistency mode for this service's backup contract.";
              };

              paths = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Raw mutable state paths included in the backup payload for this service.";
              };

              exportPaths = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Generated export artifact paths captured alongside raw state for this service.";
              };

              exclude = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Service-specific exclusions applied to the shared restic job.";
              };

              prepareCommands = lib.mkOption {
                type = lib.types.listOf lib.types.lines;
                default = [ ];
                description = "Shell commands run before the shared backup job for this service.";
              };

              cleanupCommands = lib.mkOption {
                type = lib.types.listOf lib.types.lines;
                default = [ ];
                description = "Shell commands run after the shared backup job for this service.";
              };
            };
          }
        )
      );
      default = { };
      description = "Per-service backup metadata consumed by the shared host backup module.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (secretHelpers.mkRequiredSecretAssertion {
        enable = cfg.enable;
        file = cfg.secretFile;
        feature = "services.state-backups";
        label = "secretFile";
      })
      {
        assertion = cfg.bucket != "";
        message = "services.state-backups.bucket must be set when host state backups are enabled.";
      }
      {
        assertion = allBackupPaths != [ ];
        message = "services.state-backups requires at least one service path or export artifact to back up.";
      }
    ];

    sops.secrets = secretHelpers.mkSecretsFromMap cfg.secretFile {
      state_backups_s3_access_key_id = {
        key = cfg.secretKeys.accessKeyId;
        path = "/run/secrets/state-backups.s3_access_key_id";
        owner = "root";
        group = "root";
      };
      state_backups_s3_secret_access_key = {
        key = cfg.secretKeys.secretAccessKey;
        path = "/run/secrets/state-backups.s3_secret_access_key";
        owner = "root";
        group = "root";
      };
      state_backups_restic_password = {
        key = cfg.secretKeys.resticPassword;
        path = "/run/secrets/state-backups.restic_password";
        owner = "root";
        group = "root";
      };
    };

    sops.templates."state-backups.env" = {
      owner = "root";
      group = "root";
      mode = "0400";
      content = ''
        AWS_ACCESS_KEY_ID=${config.sops.placeholder.state_backups_s3_access_key_id}
        AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.state_backups_s3_secret_access_key}
        AWS_DEFAULT_REGION=${globals.s3.region}
      '';
    };

    services.restic.backups.${cfg.backupName} = {
      initialize = true;
      repository = repository;
      environmentFile = config.sops.templates."state-backups.env".path;
      passwordFile = config.sops.secrets.state_backups_restic_password.path;
      paths = allBackupPaths;
      exclude = allExcludePaths;
      timerConfig = cfg.timerConfig;
      pruneOpts = cfg.pruneOpts;
      checkOpts = cfg.checkOpts;
      extraOptions = cfg.extraOptions;
    }
    // lib.optionalAttrs (prepareCommands != [ ]) { backupPrepareCommand = prepareScript; }
    // lib.optionalAttrs (cleanupCommands != [ ]) { backupCleanupCommand = cleanupScript; };

    # state-backups owns only the non-listable staging root and restore-staging
    # parent. Service users can traverse to their module-owned private export
    # directories (e.g. PostgreSQL's 0700 postgres-owned child).
    systemd.tmpfiles.rules = [
      "d ${cfg.stagingRoot} 0711 root root - -"
      "d /var/tmp/state-restore 0700 root root - -"
    ];

    # Failure-only monitoring for the restic backup unit: wire
    # OnFailure=svc-monitor@... directly, without the generic monitor's
    # lifecycle ExecStartPost/ExecStopPost hooks (ExecStopPost would report
    # success after a failed run). The notification-daemon monitor template
    # must exist, so monitor.enable defaults on; restic is deliberately NOT in
    # the generic monitor.services lifecycle list.
    services.notification-daemon.monitor.enable = lib.mkDefault true;
    systemd.services."restic-backups-${cfg.backupName}".onFailure = lib.mkBefore [
      "svc-monitor@restic-backups-${cfg.backupName}.service"
    ];

    # The state-restore-stage helper package (option defined by this module).
    services.state-backups.restoreStagePackage = restoreStageScript;

    environment.systemPackages = with pkgs; [
      restic
      sqlite
      restoreStageScript
    ];
  };
}
