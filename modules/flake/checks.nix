# Booted, not evaluated: a broken grant shows only when a role authenticates.
#
# x86_64-linux only: the aarch64 builder has no proven KVM, and a VM test without it fails.
{ inputs, lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    lib.mkIf pkgs.stdenv.hostPlatform.isx86_64 {
      checks.postgres-consumer-roles = import ../../tests/postgres-consumer-roles.nix {
        inherit pkgs;
        sopsModule = inputs.sops-nix.nixosModules.sops;
      };
    };
}
