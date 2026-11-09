{
  config,
  inputs,
  lib,
  ...
}:
let
  policy = import ../../policy/nixbot.nix;
  builders = inputs.nix-fleet.lib.buildProfile.resolveBuildProfile config.fleet "ci";
  builderNames = map (builder: builder.name) builders;
in
{
  flake.modules.nixos.build-account = { config, ... }: {
    users.users.${config.services.build-account.name}.openssh.authorizedKeys.keys =
      lib.optional (builtins.elem config.networking.hostName builderNames) policy.builderPublicKey;
  };
}
