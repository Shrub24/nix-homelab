# Packages service modules consume, for the evaluated host's system. An explicit
# allowlist: host-* packages embed deploy-node profiles and would recurse into the module space.
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
        inherit (inputs.nix-fleet.packages.${pkgs.stdenv.hostPlatform.system})
          notify
          bifrost-voyage-plugin
          ;
        degoog = pkgs.callPackage ../../pkgs/degoog {
          bun2nix = inputs.bun2nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
          src = inputs.degoog;
        };
        bookorbit-plugins = pkgs.callPackage ../../pkgs/bookorbit-plugins { };
      };
    };
}
