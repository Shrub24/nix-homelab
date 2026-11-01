# Repository packages. host-* are the addressable form of the deploy-profile checks,
# published unfiltered so `nix build .#host-<host>` resolves from any system.
top@{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      system,
      ...
    }:
    {
      packages = {
        inherit (pkgs) deploy-rs;
        inherit (inputs.nix-fleet.packages.${system}) bifrost bifrost-voyage-plugin;
        niks3 = inputs.niks3.packages.${system}.niks3;
        sops-bootstrap = inputs.nix-fleet.packages.${system}.sops-bootstrap;
        degoog = pkgs.callPackage ../../pkgs/degoog {
          bun2nix = inputs.bun2nix.packages.${system}.default;
          src = inputs.degoog;
        };
        windows-dj-setup = pkgs.callPackage ../../pkgs/windows-dj-setup { };
        bookorbit-plugins = pkgs.callPackage ../../pkgs/bookorbit-plugins { };
        host-la-admin-1 = top.config.flake.deploy.nodes.la-admin-1.profiles.system.path;
        host-oci-melb-1 = top.config.flake.deploy.nodes.oci-melb-1.profiles.system.path;
        host-home-forge = top.config.flake.deploy.nodes.home-forge.profiles.system.path;
      };
    };
}
