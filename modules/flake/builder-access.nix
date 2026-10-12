# Builder-access aspect: SSH trust for the hosts that offer build capability,
# derived from nix-fleet's canonical facts (D-066). Scheduling stays off — CI
# builds (TD-30), and a host that wants to offload resolves a profile in its own
# composition. This contributor is the single importer of nix-fleet's fleet
# feature: a second import re-defines perSystem.packages.ci and fails
# evaluation, so every other reader (host records, the build-account seam)
# takes config.fleet from here.
{
  lib,
  config,
  inputs,
  ...
}:
let
  resolve = inputs.nix-fleet.lib.buildProfile;

  builderHosts = lib.filterAttrs (_: host: host.capabilities.nixBuilder.enable) config.fleet.hosts;

  trustSpecs = resolve.resolveHosts config.fleet (
    lib.genAttrs (builtins.attrNames builderHosts) (_: { })
  );
in
{
  imports = [ inputs.nix-fleet.flakeModules.fleet ];

  flake.modules.nixos.builder-access = {
    programs.ssh = {
      knownHosts = resolve.knownHosts trustSpecs;
      extraConfig = resolve.sshConfig trustSpecs;
    };
  };
}
