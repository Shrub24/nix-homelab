# Foundation aspect (FND-1): shell tooling. Selecting an aspect is its
# enablement; no aspect imports another aspect. This aspect imports its own
# private NixOS leaf without creating a hidden public dependency.
{ inputs, ... }:
{
  flake.modules.nixos.shell = {
    imports = [
      inputs.nix-index-database.nixosModules.nix-index
      ./_aspects/shell.nix
    ];
  };
}
