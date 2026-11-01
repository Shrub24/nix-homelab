# nix-fleet's package-updates registry plus this repository's registrations:
# `degoog` and `windows-dj-setup`. `nix run .#update` / `.#update-packages`.
{ inputs, ... }:
{
  imports = [ inputs.nix-fleet.flakeModules.packageUpdates ];

  perSystem.packageUpdates.packages = [
    "degoog"
    "windows-dj-setup"
  ];
}
