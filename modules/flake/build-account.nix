# Build-account aspect: the inbound identity a remote build coordinator dials a
# builder host as. nix-fleet owns the account mechanism (name, working shell,
# home, empty key list); this is our fleet convention over it — the canonical
# coordinator key from the shared fleet inventory is the only one authorized, so
# a selected host accepts CI dial-in and nothing else. Authorizing that key
# grants build access, not deployment or human access: the account takes no
# sudo, no extra groups, and its home carries no state we depend on.
#
# The fleet inventory is imported once, by builder-access.nix — importing
# inputs.nix-fleet.flakeModules.fleet again re-defines perSystem.packages.ci and
# fails evaluation — so this contributor reads config.fleet instead.
#
# ssh-ng dispatch requires the account name in Nix's trusted-users list; the
# selected nix-fleet build-account aspect owns that name-derived binding. Do not
# duplicate it here. Trusted-user membership is effectively root-level Nix
# authority, so retain the canonical coordinator key and existing SSH/Tailscale
# admission boundary. This contributor owns only consumer-specific key authorization.
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
