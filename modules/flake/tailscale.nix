# Tailscale foundation aspect. nix-fleet owns the mechanism (service wiring,
# the debugMtu override, the auth-key registration); this contributor supplies
# the fleet's conventions around it: the host-scoped secret file
# (secrets/hosts/${networking.hostName}/system.yaml, key tailscale/auth_key) and
# its two-step sops bootstrap, so a host whose scope does not exist yet
# registers nothing and tailscaled stays unauthenticated until the operator
# adds it.
{ inputs, ... }:
{
  flake.modules.nixos.tailscale =
    { config, lib, ... }:
    let
      authKeyFile = ../../secrets/hosts + "/${config.networking.hostName}/system.yaml";
    in
    {
      imports = [ inputs.nix-fleet.modules.nixos.tailscale ];

      services.tailscale.secretFiles.auth = lib.mkIf (builtins.pathExists authKeyFile) authKeyFile;
    };
}
