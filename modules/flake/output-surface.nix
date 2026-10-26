# The published flake surface, default-deny: an output appears because this list
# names it, so a module's stray attribute cannot become part of the interface.
# `touchup` also drops flake-parts' empty defaults (`nixosModules`, `overlays`,
# `legacyPackages.<system>`), which otherwise advertise capabilities this
# repository does not offer to a consumer.
{ inputs, lib, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.touchup ];

  touchup = {
    any.enable = lib.mkDefault false;

    attr = {
      nixosConfigurations.enable = true;
      modules.enable = true;
      packages.enable = true;
      checks.enable = true;
      devShells.enable = true;
      formatter.enable = true;
      apps.enable = true;
      deploy.enable = true;
      fleet.enable = true;

      # nix-fleet's test fixture is upstream's surface, not this repository's:
      # nothing here, and none of its reusable workflows, reads it through this
      # flake. Restoring it is this one line.
      packages.any.attr.fixture.enable = false;
    };
  };
}
