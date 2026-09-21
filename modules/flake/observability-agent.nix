# Observability agent aspect. nix-fleet owns the Beszel agent enrollment
# mechanism (the two-step secret gate, the environment template, the agent
# service); this contributor supplies the fleet's secret conventions — the
# fleet-wide agent key in secrets/common.yaml and the host-scoped enrollment
# token in secrets/hosts/${hostname}/system.yaml — and the unit's monitoring
# participation, which only exists once that token does.
{ inputs, ... }:
{
  flake.modules.nixos.observability-agent =
    { config, lib, ... }:
    let
      hostSystemSecret = ../../secrets/hosts + "/${config.networking.hostName}/system.yaml";
      hasHostSecrets = builtins.pathExists hostSystemSecret;
    in
    {
      imports = [ inputs.nix-fleet.modules.nixos.beszel-agent ];

      services.beszel-agent.secretFiles = {
        common = ../../secrets/common.yaml;
        host = lib.mkIf hasHostSecrets hostSystemSecret;
      };

      services.notify.events."beszel-agent" = lib.mkIf hasHostSecrets {
        failure = { };
      };
    };
}
