# Observability agent aspect. nix-fleet owns the Beszel agent enrollment
# mechanism: the two-step secret gate, the environment template, the agent
# service, and the failure registration for the unit it creates. This contributor
# supplies only the fleet's secret conventions — the fleet-wide agent key in
# secrets/common.yaml, and the host-scoped secrets file whose presence gates
# enrollment. There is no host-scoped credential: the agent authenticates the
# hub with that shared key over SSH.
{ inputs, ... }:
{
  flake.modules.nixos.observability-agent =
    { config, lib, ... }:
    let
      hostSystemSecret = ../../secrets/hosts + "/${config.networking.hostName}/system.yaml";
    in
    {
      imports = [ inputs.nix-fleet.modules.nixos.beszel-agent ];

      services.beszel-agent.secretFiles = {
        common = ../../secrets/common.yaml;
        host = lib.mkIf (builtins.pathExists hostSystemSecret) hostSystemSecret;
      };
    };
}
