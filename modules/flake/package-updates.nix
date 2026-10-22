# nix-fleet's package-updates registry plus this repository's registrations:
# `degoog`, `geopulse` (one pin, coupled updater) and `windows-dj-setup`.
# `nix run .#update` / `.#update-packages`.
{ inputs, ... }:
{
  imports = [ inputs.nix-fleet.flakeModules.packageUpdates ];

  perSystem.packageUpdates.packages = [
    "degoog"
    "geopulse"
    "windows-dj-setup"
  ];
}
