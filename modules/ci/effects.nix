# The repository's nixbot effects in one output: main-push retention and the
# scheduled update transaction. The bodies live beside this file, because
# flake-parts cannot merge two functions into one output.
{
  config,
  inputs,
  lib,
  ...
}:
let
  pkgs = inputs.nixpkgs.legacyPackages.${config.nixos.hosts.home-forge.system};
  effects = inputs.nixbot.lib.effects { inherit pkgs; };
  args = {
    inherit
      config
      lib
      pkgs
      effects
      ;
  };
  cacheRetain = import ./_cache-retain.nix args;
  packageUpdates = import ./_package-updates.nix args;
in
{
  flake.herculesCI =
    { primaryRepo, ... }:
    {
      onPush.default.outputs.effects = cacheRetain primaryRepo;
      onSchedule.package-updates = packageUpdates primaryRepo;
    };
}
