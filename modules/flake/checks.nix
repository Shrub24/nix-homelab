# Checks built from a booted node rather than evaluated from the configuration. The substrate's
# provisioning SQL and pg_hba rendering are ours, so they are proven by authenticating as the
# roles they create; nothing a static assertion can see would catch a broken grant.
#
# x86_64-linux only: the fleet's x86_64 builder provides KVM, the aarch64 one has not been shown
# to, and a VM test without it fails rather than skips.
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
