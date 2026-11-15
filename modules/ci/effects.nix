# This repository's CI interface, from nix-fleet's `ci` module: main-push and
# tag retention, and the scheduled update transaction. The operator plane
# (`ciFederation`) reconciles the enrolled repositories from the same list that
# drives the cache's trust rules and the controller's allowlist.
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
    repositories = import ../../policy/ci-repositories.nix;
    appId = policy.github.appId;
    installationId = null;
    nixbotUrl = home-forge.config.repo.web.catalog.nixbot.publicUrl;
  };
}
