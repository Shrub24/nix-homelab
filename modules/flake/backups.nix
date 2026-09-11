# Operational aspect (dendritic stage 3, OPS-1).
# Backups: host-egress capability composing state backups, the niks3 upload
# client, and post-deploy closure upload. Selection is enablement; the aspect
# imports the upstream niks3-auto-upload module itself and injects the
# required nix-path-filter package per system via withSystem, so it has no
# hidden fleet-packages dependency. The conventional host secret path gates
# the whole capability (two-step sops bootstrap, OPS-3).
{ inputs, withSystem, ... }:
{
  flake.modules.nixos.backups =
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
      # S3 bucket rule (OPS-11): 3-63 chars, lowercase alnum/hyphens, alnum at both ends.
      bucketNameValid = builtins.match "^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$" bucketName != null;
      packages = withSystem pkgs.stdenv.hostPlatform.system (
        { config, ... }:
        {
          inherit (config.packages) nix-path-filter;
        }
      );
    in
    {
      imports = [
        inputs.niks3.nixosModules.niks3-auto-upload
        ../services/state-backups.nix
        ../shared/niks3-upload-client.nix
        ../shared/niks3-post-deploy.nix
      ];

      # The whole host-egress capability activates only when the conventional
      # host secret exists; the client leaf gates itself on the same path
      # (OPS-5). The derived bucket and secret path replace the three host
      # literals, which all equal the convention exactly.
      services.state-backups = lib.mkIf hasHostSecrets {
        enable = true;
        secretFile = hostSystemSecret;
        bucket = lib.mkDefault bucketName;
      };

      services.niks3-post-deploy = lib.mkIf hasHostSecrets {
        enable = true;
        filterPackage = packages.nix-path-filter;
      };

      assertions = [
        {
          assertion = bucketNameValid;
          message = "backups aspect: derived bucket '${bucketName}' must be a valid S3 bucket name (3-63 lowercase alnum/hyphen).";
        }
      ]
      ++ lib.optionals hasHostSecrets [
        {
          # OPS-4: backups never imports notify; it asserts the actual monitor
          # option so a host selecting backups without notify fails with a named
          # message instead of silently missing its failure-monitoring template.
          assertion = lib.attrByPath [ "services" "notification-daemon" "monitor" "enable" ] false config;
          message = "backups aspect: services.notification-daemon.monitor.enable must be true (select the notify aspect) so restic-backups-state failures route through svc-monitor.";
        }
      ];
    };
}
