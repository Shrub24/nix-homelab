# Operational aspect (split-state-backups-cache-publication, OPSPLIT-1).
# Cache publication: the Niks3 closure-upload capability only. Selection is
# enablement; the aspect imports the upstream niks3-auto-upload module
# itself, the private upload-client/post-deploy leaves, and injects the
# nix-path-filter package per system via withSystem, so it has no hidden
# fleet-packages dependency. It owns no restic state recovery; mutable
# state backups are owned by the separate state-backups aspect.
{ inputs, withSystem, ... }:
{
  flake.modules.nixos.cache-publisher =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hostSystemSecret = ../../secrets/hosts + "/${config.networking.hostName}/system.yaml";
      hasHostSecrets = builtins.pathExists hostSystemSecret;
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
        ./_backups/niks3-upload-client.nix
        ./_backups/niks3-post-deploy.nix
      ];

      # Closure publication activates only when the conventional host secret
      # exists (OPS-3); the client leaf gates itself on the same path.
      services.niks3-post-deploy = lib.mkIf hasHostSecrets {
        enable = true;
        filterPackage = packages.nix-path-filter;
      };

      assertions = lib.optionals hasHostSecrets [
        {
          # OPS-4: this aspect never imports notify; it asserts the actual
          # monitor option so a host selecting cache-publisher without notify
          # fails with a named message instead of silently missing its
          # failure-monitoring template.
          assertion = lib.attrByPath [ "services" "notification-daemon" "monitor" "enable" ] false config;
          message = "cache-publisher aspect: services.notification-daemon.monitor.enable must be true (select the notify aspect) so Niks3 upload failures route through svc-monitor.";
        }
      ];
    };
}
