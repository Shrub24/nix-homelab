# State-backup declaration surface.
#
# Declaration-only fragment: the options a participant writes or reads — the
# per-service registry a feature registers its mutable state in, plus the
# host-level capture settings a producer needs to place its export. No
# configuration here.
#
# Import this where a feature registers state; the state-backups mechanism
# imports it too, so both sides share one declaration surface and a host that
# does not run backups still evaluates its features.
{ lib, ... }:
let
  globals = import ../../policy/globals.nix;
  secretHelpers = import ../../lib/secrets.nix { inherit lib; };
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
}
