# Cache publication: the Niks3 closure-upload capability only. Selection is
# enablement; the aspect imports the upstream niks3-auto-upload module, injects
# the nix-path-filter package per system, and owns the enablement its sibling
# contributors render, so it has no hidden fleet-packages dependency. Mutable
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
      imports = [ inputs.niks3.nixosModules.niks3-auto-upload ];

      # Publication activates only when the conventional host secret exists; the
      # client leaf gates itself on the same path.
      services.niks3-post-deploy = lib.mkIf hasHostSecrets {
        enable = true;
        filterPackage = packages.nix-path-filter;
      };

      assertions = lib.optionals hasHostSecrets [
        {
          # Assert the actual monitor option rather than importing notify: a host
          # selecting cache-publisher without notify fails with a named message
          # instead of silently missing its failure-monitoring template.
          assertion = lib.attrByPath [ "services" "notification-daemon" "monitor" "enable" ] false config;
          message = "cache-publisher aspect: services.notification-daemon.monitor.enable must be true (select the notify aspect).";
        }
      ];
    };
}
