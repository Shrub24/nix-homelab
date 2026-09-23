# Builder-access aspect. nix-fleet is the authority for the fleet's canonical
# topology: machine identity, builder participation and the named builder sets
# (`fleet.hosts` / `fleet.builders` / `fleet.builderSets`) live in its
# inventory. This contributor declares none of it — a canonical fact is
# derived, never restated (D-066) — it only publishes our aspect as the
# realization, so a selecting host gets SSH trust for the inventory's hosts.
#
# INTERIM (TD-31): nix-fleet publishes the fleet feature as a pre-evaluated
# module value, so importing `flakeModules.fleet` binds the provider's own
# evaluation — the consumer receives no inventory (`config.fleet.*` stays
# empty), while the feature's CI bundles and `config.fleet.realization` close
# over nix-fleet's inventory instead of ours. Until the feature is published as
# a module function that imports its inventory, consume the canonical pieces
# directly. This collapses to `imports = [ inputs.nix-fleet.flakeModules.fleet ]`
# plus `imports = [ config.fleet.realization ]` once that lands.
#
# Scheduling is deliberately off — `services.fleet-builders.activeSet` stays
# null on every host, so a selecting host gets trust without `nix.buildMachines`.
# The fleet builds in CI, which coordinates builders by architecture (TD-30);
# local iteration builds on the workstation. A host that should offload to a
# peer sets `activeSet` in its own host-private composition.
{ inputs, config, ... }:
let
  nixFleet = inputs.nix-fleet.outPath;
in
{
  imports = [
    (import (nixFleet + "/modules/fleet/schema.nix"))
    (import (nixFleet + "/modules/fleet/inventory.nix"))
  ];

  # The realization is constructed in THIS evaluation with our merged fleet
  # config closed over; nix-fleet's pre-realized `modules.nixos.fleet-builders`
  # is a throwing shim for exactly that reason.
  flake.modules.nixos.builder-access = {
    imports = [ (import (nixFleet + "/lib/fleet-realization.nix") config.fleet) ];
  };
}
