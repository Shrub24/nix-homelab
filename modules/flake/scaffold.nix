# The fleet's system set. The aspect namespace (flake.modules) and the discovery
# wiring come from flake-file's dendritic preset in modules/flake/flake-file.nix;
# this narrows the preset's flakeExposed default to the systems the fleet builds.
{ ... }:
{
  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
}
