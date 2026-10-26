# Binds the host-selected `identity-provider` aspect to the provider policy names active:
# one switch, so a cutover cannot leave the composition pointing at the old provider.
{ config, ... }:
let
  identityPolicy = import ../../policy/identity.nix;
  active = "${identityPolicy.provider}-identity";
in
{
  flake.modules.nixos.identity-provider =
    if config.flake.modules.nixos ? ${active} then
      config.flake.modules.nixos.${active}
    else
      throw "identity-provider: policy/identity.nix selects '${identityPolicy.provider}' but the '${active}' aspect is not published";
}
