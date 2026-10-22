# SSH trust for hosts that offer build capability, from the canonical inventory. The single
# importer of the fleet feature, so every other reader takes config.fleet from here.
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
