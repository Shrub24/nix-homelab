# flake-parts core wiring: the aspect namespace and the system set.
{ inputs, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.modules ];

  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
}
