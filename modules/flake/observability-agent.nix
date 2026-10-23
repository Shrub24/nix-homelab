# Beszel agent mechanism, configured with the hub's public key (policy data, no secret).
# No enable gate: importing it selects it.
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

    # node-exporter is its own aspect; this one stays the Beszel agent mechanism alone.
  };
}
