# Foundation aspect (FND-1): networking. Selecting an aspect is its
# enablement; no aspect imports another aspect. This aspect imports its own
# private NixOS leaf without creating a hidden public dependency.
{ ... }:
{
  flake.modules.nixos.networking = {
    imports = [ ./_aspects/networking.nix ];
  };
}
