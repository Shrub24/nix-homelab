# Repository packages (perSystem). The host-* entries are the addressable form
# of the deploy-profiles published as `checks.<system>.host-*`: published
# unfiltered so `nix build .#host-<host>` resolves the activatable profile from
# any evaluating system, including a cross-system prebuild.
top@{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      config,
      system,
      ...
    }:
    let
      # GeoPulse is BUSL-1.1, which nixpkgs marks unfree. This package set admits
      # those names and nothing else; every other output stays on the default
      # refusal.
      geopulsePkgs = import pkgs.path {
        inherit system;
        overlays = pkgs.overlays;
        config = pkgs.config // {
          allowUnfreePredicate =
            pkg:
            builtins.elem (pkgs.lib.getName pkg) [
              "geopulse"
              "geopulse-backend"
              "geopulse-frontend"
            ];
        };
      };
    in
    {
      packages = {
        inherit (pkgs) deploy-rs;
        inherit (inputs.nix-fleet.packages.${system}) bifrost bifrost-voyage-plugin;
        niks3 = inputs.niks3.packages.${system}.niks3;
        sops-bootstrap = inputs.nix-fleet.packages.${system}.sops-bootstrap;
        windows-dj-setup = pkgs.callPackage ../../pkgs/windows-dj-setup { };
        inherit (geopulsePkgs.callPackage ../../pkgs { })
          geopulse
          geopulse-backend
          geopulse-frontend
          ;
        host-la-admin-1 = top.config.flake.deploy.nodes.la-admin-1.profiles.system.path;
        host-oci-melb-1 = top.config.flake.deploy.nodes.oci-melb-1.profiles.system.path;
        host-home-forge = top.config.flake.deploy.nodes.home-forge.profiles.system.path;
      };
    };
}
