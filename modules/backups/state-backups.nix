# State backups: restic state recovery and its failure monitoring only.
# Selection is enablement; the aspect imports the restic leaf and owns the
# conventional host secret gate (two-step sops bootstrap). Cache publication is
# owned by the separate cache-publisher aspect.

_: {
  flake.modules.nixos.state-backups =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hostSystemSecret = ../../secrets/hosts + "/${config.networking.hostName}/system.yaml";
      hasHostSecrets = builtins.pathExists hostSystemSecret;
      bucketName = "shrublab-backup-${config.networking.hostName}";
      # S3 bucket naming rule: 3-63 chars, lowercase alnum/hyphens, alnum at both ends.
      bucketNameValid = builtins.match "^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$" bucketName != null;

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
      imports = [ ./state-backups/_consumer.nix ];
      config = lib.mkMerge [
        (lib.mkIf cfg.enable {
          assertions = [
            (secretHelpers.mkRequiredSecretAssertion {
              inherit (cfg) enable;
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
            inherit repository;
            environmentFile = config.sops.templates."state-backups.env".path;
            passwordFile = config.sops.secrets.state_backups_restic_password.path;
            paths = allBackupPaths;
            exclude = allExcludePaths;
            inherit (cfg) timerConfig;
            inherit (cfg) pruneOpts;
            inherit (cfg) checkOpts;
            inherit (cfg) extraOptions;
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

          # Failure-only monitoring: OnFailure=svc-monitor@... is wired directly,
          # without the generic monitor's lifecycle hooks (ExecStopPost would
          # report success after a failed run).
          systemd.services."restic-backups-${cfg.backupName}".onFailure = lib.mkBefore [
            "svc-monitor@restic-backups-${cfg.backupName}.service"
          ];

          # The state-restore-stage helper package (option defined by this module).
          services.state-backups.restoreStagePackage = restoreStageScript;

          environment.systemPackages = [
            pkgs.restic
            pkgs.sqlite
            restoreStageScript
          ];
        })
        {
          # The restic capability activates only when the conventional host
          # secret exists.
          services.state-backups = lib.mkIf hasHostSecrets {
            enable = true;
            secretFile = hostSystemSecret;
            bucket = lib.mkDefault bucketName;
          };

          assertions = [
            {
              assertion = bucketNameValid;
              message = "state-backups aspect: derived bucket '${bucketName}' must be a valid S3 bucket name (3-63 lowercase alnum/hyphen).";
            }
          ]
          ++ lib.optionals hasHostSecrets [
            {
              # Assert the actual monitor option rather than importing notify: a
              # host selecting state-backups without notify fails with a named
              # message instead of silently missing the monitor template.
              assertion = lib.attrByPath [ "services" "notification-daemon" "monitor" "enable" ] false config;
              message = "state-backups aspect: services.notification-daemon.monitor.enable must be true (select the notify aspect) so restic-backups-state failures route through svc-monitor.";
            }
          ];
        }
      ];
    };
}
