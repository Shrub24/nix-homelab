# Repository packages consumable by service modules, resolved for the evaluated
# host's target system. Explicit allowlist: host-* convenience packages embed
# deploy-node profile paths that depend on nixosConfigurations, so projecting
# the full perSystem attrset would recurse back into the module space.
#
# The `notify` CLI is a shipped implementation, not a repository package: the
# notification mechanism moved to nix-fleet (D-061), so the bus re-exports the
# fleet's package instead of building a local copy. Consumers that only need the
# CLI keep resolving it here.
{
  inputs,
  lib,
  ...
}:
{
  flake.modules.nixos.fleet-packages =
    { pkgs, ... }:
    {
      options.repo.packages = lib.mkOption {
        type = lib.types.attrs;
        readOnly = true;
        description = "Service-consumable repository packages for this host's target system.";
      };

      config.repo.packages = {
        inherit (inputs.nix-fleet.packages.${pkgs.stdenv.hostPlatform.system}) notify;
      };
    };
}
