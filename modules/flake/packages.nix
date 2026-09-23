# Repository packages (perSystem). The host-* entries track the deploy node
# activation paths.
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
        windows-dj-setup = pkgs.callPackage ../../pkgs/windows-dj-setup { };
        host-la-admin-1 = top.config.flake.deploy.nodes.la-admin-1.profiles.system.path;
        host-oci-melb-1 = top.config.flake.deploy.nodes.oci-melb-1.profiles.system.path;
      };
    };
}
