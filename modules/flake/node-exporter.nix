# node-exporter aspect: publishes the shared exporter mechanism under our aspect
# name — the loopback bind, the scrape registration and the failure notification
# are nix-fleet's, and so is the scrape target's identity: `instance` defaults to
# `<hostName>:<port>`, distinct per host because canonical host IDs are unique and
# the host registry fails closed on duplicates. No fleet convention is left to
# bind, so this contributor only keeps our aspect name over that mechanism.
{ inputs, ... }:
{
  flake.modules.nixos.node-exporter = {
    imports = [ inputs.nix-fleet.modules.nixos.node-exporter ];
  };
}
