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
      # nixbot evaluates the effects through this output; dropping it leaves the
      # repository with no effects at all.
      herculesCI.enable = true;

      # nix-fleet's test fixtures are upstream's surface, not this repository's:
      # nothing here, and none of its reusable workflows, reads them through this
      # flake. Restoring one is that one line.
      packages.any.attr.fixture.enable = false;
      checks.any.attr.fleet-render.enable = false;
      checks.any.attr.ci-tailscale.enable = false;
    };
  };
}
