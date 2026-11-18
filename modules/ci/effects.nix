# This repository's CI interface, from nix-fleet's `ci` module: main-push and
# tag retention, and the scheduled update transaction. The instance is nix-fleet's
# canonical `lib.ci.instance`.
{ config, inputs, ... }:
let
  inherit (config.flake.nixosConfigurations) home-forge;
  policy = import ../../policy/nixbot.nix;
in
{
  imports = [ inputs.nix-fleet.flakeModules.ci ];

  ci = {
    nixPackage = home-forge.config.nix.package;
    niks3Package = config.flake.packages.${config.ci.instance.system}.niks3;
    retention = {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      generations = 3;
    };
    updates.autoMerge = policy.updateAutoMerge;
  };
}
