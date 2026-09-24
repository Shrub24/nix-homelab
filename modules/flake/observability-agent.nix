# Observability-agent aspect: the shared Beszel agent mechanism, configured with
# the hub's public key (fleet policy data — the agent holds no secret; the aspect
# itself has no enable gate, so importing it selects it).
{ inputs, ... }:
let
  globals = import ../../policy/globals.nix;
in
{
  flake.modules.nixos.observability-agent = {
    imports = [ inputs.nix-fleet.modules.nixos.beszel-agent ];

    services.beszel-agent = {
      key = globals.beszel.hubKey;
    };

    # node-exporter is its own aspect now: selecting it binds the loopback
    # listener, registers the local scrape source, and owns its own failure
    # notification, so this aspect stays the Beszel agent mechanism alone.
  };
}
