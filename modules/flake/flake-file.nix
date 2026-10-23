# flake.nix is generated: `nix run .#write-flake` renders it from the input and description
# declarations here. `systems` narrows the default set to the two the fleet builds for.
{ inputs, ... }:
{
  imports = [ inputs.flake-file.flakeModules.dendritic ];

  flake-file.description = "Modular NixOS fleet infrastructure";

  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
}
