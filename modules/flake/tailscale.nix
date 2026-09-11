# Foundation aspect (FND-1): Tailscale. Selecting an aspect is its
# enablement; no aspect imports another aspect. This aspect imports its own
# service leaf without creating a hidden public dependency.
{ ... }:
{
  flake.modules.nixos.tailscale = {
    imports = [ ../services/tailscale.nix ];
  };
}
