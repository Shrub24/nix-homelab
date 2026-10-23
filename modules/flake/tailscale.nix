# nix-fleet owns the mechanism; this binds the host-scoped auth key at
# secrets/hosts/<host>/system.yaml:tailscale/auth_key. An absent scope registers nothing.
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
