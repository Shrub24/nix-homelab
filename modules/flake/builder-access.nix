# Builder-access aspect. nix-fleet owns the builder control plane: the typed
# fleet registry (`fleet.hosts` / `fleet.builders` / `fleet.builderSets`) and the
# NixOS realization constructed from it (`fleet-builders`: SSH trust for registry
# hosts, plus `nix.buildMachines` scheduling from a named builder set). This
# contributor imports both flake-level modules, declares the fleet's build
# inventory, and publishes the aspect.
#
# Scheduling is deliberately off — `services.fleet-builders.activeSet` stays null
# on every host, so a selecting host gets trust without `nix.buildMachines`. The
# fleet builds in CI, which coordinates builders by architecture; local
# iteration builds on the workstation. A host that should offload to a peer sets
# `activeSet` in its own host-private composition.
{ inputs, config, ... }:
{
  imports = [
    inputs.nix-fleet.flakeModules.registry
    inputs.nix-fleet.flakeModules.fleet-builders
  ];

  # Build profiles: what each host contributes when a build is dispatched to it.
  # maxJobs and speedFactor follow observed capacity (OCI 4 vCPU/23 GB,
  # la-admin-1 2 vCPU/3 GB, home-forge 12 cores/31 GB) and stay conservative
  # because these hosts also run the services they build for. Features are
  # declared only where the hardware supports them.
  fleet.builders = {
    oci-melb-1 = {
      host = "oci-melb-1";
      systems = [ "aarch64-linux" ];
      maxJobs = 4;
      speedFactor = 2;
      supportedFeatures = [ "big-parallel" ];
    };

    la-admin-1 = {
      host = "la-admin-1";
      systems = [ "x86_64-linux" ];
      maxJobs = 2;
      speedFactor = 1;
    };

    home-forge = {
      host = "home-forge";
      systems = [ "x86_64-linux" ];
      maxJobs = 6;
      speedFactor = 4;
      supportedFeatures = [
        "big-parallel"
        "kvm"
        "nixos-test"
      ];
    };
  };

  # The one scheduling policy: named sets of builders a consumer may draw on.
  # `ci` is the fleet capacity CI uses for architectures its own runners cover
  # poorly; the CI workflow installs the rendered `packages.ci-builders` bundle.
  fleet.builderSets.ci = [ "oci-melb-1" ];

  # The realization is constructed per consumer: importing the flake-level
  # module builds `flake.modules.nixos.fleet-builders` in THIS evaluation with
  # this fleet's registry closed over. nix-fleet's published
  # `inputs.nix-fleet.modules.nixos.fleet-builders` is bound to nix-fleet's own
  # (fixture) registry and must never be imported here.
  flake.modules.nixos.builder-access = {
    imports = [ config.flake.modules.nixos.fleet-builders ];
  };
}
