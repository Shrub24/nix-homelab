# Publishes nix-fleet's exporter mechanism under our aspect name. It has no convention
# left to bind, so this is only the name.
{ inputs, ... }:
{
  flake.modules.nixos.node-exporter = {
    imports = [ inputs.nix-fleet.modules.nixos.node-exporter ];
  };
}
