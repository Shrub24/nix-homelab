# Operational aspect (split-state-backups-cache-publication, OPSPLIT-1).
# State backups: restic state recovery and its feature-owned failure
# monitoring only. Selection is enablement; the aspect imports the restic
# leaf itself and owns the conventional host secret gate (two-step sops
# bootstrap, OPS-3). It deliberately imports no Niks3 upload/publication
# leaves and no sibling public aspect; cache publication is owned by the
# separate cache-publisher aspect.
{
  flake.modules.nixos.state-backups =
    {
      config,
      lib,
      ...
    }:
    let
      hostSystemSecret = ../../secrets/hosts + "/${config.networking.hostName}/system.yaml";
      hasHostSecrets = builtins.pathExists hostSystemSecret;
      bucketName = "shrublab-backup-${config.networking.hostName}";
      # S3 bucket rule (OPS-11): 3-63 chars, lowercase alnum/hyphens, alnum at both ends.
      bucketNameValid = builtins.match "^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$" bucketName != null;
    in
    {
      imports = [
        ../services/state-backups.nix
      ];

      # The restic capability activates only when the conventional host
      # secret exists (OPS-3). The derived bucket and secret path replace
      # the host literals, which all equal the convention exactly.
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
          # OPS-4: this aspect never imports notify; it asserts the actual
          # monitor option so a host selecting state-backups without notify
          # fails with a named message instead of silently missing its
          # failure-monitoring template.
          assertion = lib.attrByPath [ "services" "notification-daemon" "monitor" "enable" ] false config;
          message = "state-backups aspect: services.notification-daemon.monitor.enable must be true (select the notify aspect) so restic-backups-state failures route through svc-monitor.";
        }
      ];
    };
}
