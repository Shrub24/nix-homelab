# Foundation aspect (FND-1): notifications. Selecting an aspect is its
# enablement; no aspect imports another aspect. This aspect imports its own
# service leaf without creating a hidden public dependency.
{ withSystem, ... }:
{
  flake.modules.nixos.notify =
    { pkgs, ... }:
    let
      packages = withSystem pkgs.stdenv.hostPlatform.system (
        { config, ... }:
        {
          inherit (config.packages) notification-daemon notify;
        }
      );
    in
    {
      imports = [ ../services/notification-daemon ];
      services.notification-daemon = {
        enable = true;
        package = packages.notification-daemon;
        notifyPackage = packages.notify;
        # OPS-4: notify owns monitor composition (canonical apprise contract).
        # The state-backups leaf no longer defaults monitor.enable on; the
        # backups aspect asserts this option instead of importing notify.
        monitor.enable = true;
      };
    };
}
