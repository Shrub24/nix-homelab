# The inbound build account: nix-fleet owns the mechanism, and the canonical coordinator
# key is the only one authorized. Read config.fleet; a second fleet import fails evaluation.
{
  config,
  inputs,
  ...
}:
let
  coordinatorPublicKey = config.fleet.ci.sshPublicKey;
in
{
  flake.modules.nixos.build-account =
    { config, ... }:
    {
      imports = [ inputs.nix-fleet.modules.nixos.build-account ];

      users.users.${config.services.build-account.name}.openssh.authorizedKeys.keys = [
        coordinatorPublicKey
      ];
    };
}
