# Repository packages consumable by service modules, resolved for the
# evaluated host's target system (replaces self.packages.${...} in leaf
# modules). Explicit allowlist: host-* convenience packages embed deploy-node
# profile paths that depend on nixosConfigurations, so projecting the full
# perSystem attrset would open a recursion back into the module space.
{ lib, withSystem, ... }:
{
  flake.modules.nixos.fleet-packages =
    { pkgs, ... }:
    {
      options.repo.packages = lib.mkOption {
        type = lib.types.attrs;
        readOnly = true;
        description = "Service-consumable repository packages for this host's target system.";
      };

      config.repo.packages = withSystem pkgs.stdenv.hostPlatform.system (
        { config, ... }:
        {
          inherit (config.packages)
            nix-path-filter
            notification-daemon
            notify
            ;
        }
      );
    };
}
