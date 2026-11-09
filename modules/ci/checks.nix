# nixbot's contracts: the service wiring an operator cannot verify by reading the
# module, and the two effects' decision paths.
#
# x86_64-linux only: the coordinator's own package and roots are read here.
{ config, lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    lib.mkIf (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
      checks.nixbot-contract = import ../../tests/nixbot-contract.nix { inherit config lib pkgs; };
      checks.cache-retain = import ../../tests/cache-retain-contract.nix { inherit config lib pkgs; };
      checks.package-updates = import ../../tests/package-updates-contract.nix {
        inherit config lib pkgs;
      };
    };
}
