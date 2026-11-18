# The inbound build account: nix-fleet owns the mechanism. The key it accepts is
# the nixbot controller's, authorized in modules/ci/nixbot-build-account.nix.
{ inputs, ... }:
{
  flake.modules.nixos.build-account = {
    imports = [ inputs.nix-fleet.modules.nixos.build-account ];
  };
}
