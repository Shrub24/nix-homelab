# flake-parts core wiring (DS-1): aspect namespace + the exact system set
# Stage 0 exposed (devShells, packages, formatter, checks).
{ inputs, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.modules ];

  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
}
