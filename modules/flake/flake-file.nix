# flake.nix is generated: `nix run .#write-flake` renders it from the input and
# description declarations in this tree. The dendritic preset declares the
# flake.modules namespace, wires flake-parts and import-tree discovery, and
# sets the default system set, which `systems` below narrows to the two systems
# the fleet builds for.
{ inputs, ... }:
{
  imports = [ inputs.flake-file.flakeModules.dendritic ];

  flake-file.description = "Modular NixOS fleet infrastructure";

  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
}
