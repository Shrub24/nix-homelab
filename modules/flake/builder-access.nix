# Builder-access aspect. nix-fleet is the authority for the fleet's canonical
# topology: machine identity, builder participation and the named builder sets
# (`fleet.hosts` / `fleet.builders` / `fleet.builderSets`) live in its
# inventory, and its `fleet` flakeModule composes the schema, that inventory,
# the fail-closed validation and the CI builder bundles. This contributor
# declares none of it — a canonical fact is derived, never restated (D-066) —
# it only publishes our aspect as the realization, so a selecting host gets SSH
# trust for the inventory's hosts.
#
# The realization is constructed in THIS evaluation, not read from
# `config.fleet.realization`: nix-fleet still publishes the feature as a
# pre-evaluated value, so that value closes over nix-fleet's own `config.fleet`
# and renders ITS records — measured, not assumed: importing it made every host
# trust `builder-fixture-external` and `host-fixture-host` alongside the real
# fleet, and `packages` gained nix-fleet's `fixture` builder set. The same
# closure is why nix-fleet's pre-realized `modules.nixos.fleet-builders` is a
# throwing shim. Once the feature is published as a module function (so every
# closure binds the consumer), this collapses to `imports = [ config.fleet.realization ]`.
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
  imports = [ inputs.nix-fleet.flakeModules.fleet ];

  flake.modules.nixos.builder-access = {
    imports = [ (import (nixFleet + "/lib/fleet-realization.nix") config.fleet) ];
  };
}
