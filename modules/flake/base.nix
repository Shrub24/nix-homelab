# Foundation aspect (FND-1): base server policy. Selecting an aspect is its
# enablement; no aspect imports another aspect. This aspect imports its own
# private NixOS leaf without creating a hidden public dependency.
{ ... }:
{
  flake.modules.nixos.base = {
    imports = [ ./_aspects/base.nix ];
  };
}
