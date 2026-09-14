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

      # MON-1/MON-3: this aspect owns the `beszel-agent` unit through the auth
      # leaf, so it also owns its monitoring participation. The unit only exists
      # once the conventional host secret exists, so the contribution is gated
      # on the same two-step bootstrap predicate (no phantom target).
      services.notification-daemon.monitor.units."beszel-agent" = lib.mkIf hasHostSecrets {
        onFailure = true;
        onStart = true;
        onStop = true;
      };
    };
}
