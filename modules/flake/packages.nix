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
    {
      packages = {
        inherit (pkgs) deploy-rs;
        inherit (inputs.nix-fleet.packages.${system}) bifrost bifrost-voyage-plugin;
        niks3 = inputs.niks3.packages.${system}.niks3;
        sops-bootstrap = inputs.nix-fleet.packages.${system}.sops-bootstrap;
        windows-dj-setup = pkgs.callPackage ../../pkgs/windows-dj-setup { };
        host-la-admin-1 = top.config.flake.deploy.nodes.la-admin-1.profiles.system.path;
        host-oci-melb-1 = top.config.flake.deploy.nodes.oci-melb-1.profiles.system.path;
        host-home-forge = top.config.flake.deploy.nodes.home-forge.profiles.system.path;
      };
    };
}
