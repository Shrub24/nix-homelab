# Repository packages (perSystem). Stage 0 key set preserved exactly; the
# host-* convenience packages track the deploy node activation paths as before.
top@{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      config,
      system,
      ...
    }:
    {
      packages = {
        inherit (pkgs) deploy-rs;
        niks3 = inputs.niks3.packages.${system}.niks3;
        nix-path-filter = pkgs.callPackage ../../pkgs/nix-path-filter { };
        notification-daemon = pkgs.callPackage ../../pkgs/notification-daemon { };
        notify = pkgs.callPackage ../../pkgs/notify { };
        windows-dj-setup = pkgs.callPackage ../../pkgs/windows-dj-setup { };
        host-la-admin-1 = top.config.flake.deploy.nodes.la-admin-1.profiles.system.path;
        host-oci-melb-1 = top.config.flake.deploy.nodes.oci-melb-1.profiles.system.path;
      };
    };
}
