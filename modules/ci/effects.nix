# This repository's CI interface, from nix-fleet's `ci` module: main-push and
# tag retention, and the scheduled update transaction. `ciFederation` supplies
# the instance facts `nix run .#ci-enrol -- [OWNER/REPO]` enrols repositories with.
{ config, inputs, ... }:
let
  inherit (config.flake.nixosConfigurations) home-forge;
  policy = import ../../policy/nixbot.nix;
  instance = import ../../ci/instance.nix;
in
{
  imports = [
    inputs.nix-fleet.flakeModules.ci
    inputs.nix-fleet.flakeModules.ciFederation
  ];

  ci = {
    inherit instance;
    nixPackage = home-forge.config.nix.package;
    niks3Package = config.flake.packages.${instance.system}.niks3;
    retention = {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      generations = 3;
    };
    updates = {
      when = {
        minute = 43;
        hour = [ 4 ];
        dayOfWeek = [ "Mon" ];
      };
      autoMerge = policy.updateAutoMerge;
    };
  };

  ciFederation = {
    appId = policy.github.appId;
    nixbotUrl = home-forge.config.repo.web.catalog.nixbot.publicUrl;
  };
}
