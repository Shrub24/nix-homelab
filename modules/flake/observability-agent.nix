# Observability agent: Beszel agent authentication and enrollment (OPS-8).
# The aspect derives the conventional host secret path and gates enrollment
# on its existence; the Beszel hub remains an admin-service leaf.
{ ... }:
{
  flake.modules.nixos.observability-agent =
    { config, lib, ... }:
    let
      hostSystemSecret = ../../secrets/hosts + "/${config.networking.hostName}/system.yaml";
      hasHostSecrets = builtins.pathExists hostSystemSecret;
    in
    {
      imports = [ ../services/beszel-agent-auth.nix ];

      services.beszel-agent-auth = lib.mkIf hasHostSecrets {
        enable = true;
        secretFiles.host = hostSystemSecret;
      };
    };
}
