# home-forge host contributor (Stage 8 HIC-1/HIC-2, task 2.2). This file is the
# host entry point: it declares the canonical typed host record — target system,
# Tailscale identity, deferred NixOS composition, and SSH/deploy facts. The
# NixOS composition itself stays host-private in `_nixos.nix` (plus the
# `_disko-two-disk.nix` layout), so a host assembly can never be selected as a
# public aspect.
#
# This contributor is reached by `denful/import-tree` discovery like every
# other module: stage 8 task 2.3 removed the `hosts` import-tree exclusion
# together with the transitional loader, and `modules/flake/registry.nix` is
# now only the `flake.bootstrap.nodes` projection over these records.
{
  config,
  inputs,
  ...
}:
let
  aspects = config.flake.modules.nixos;
in
{
  nixos.hosts.home-forge = {
    system = "x86_64-linux";

    tailscale = {
      hostname = "home-forge";
      # Stage 8 task 3.2 (HIC-3): single authority in policy/globals.nix
      # `tailnet.suffix`; the web policy reads the same value.
      tailnetSuffix = (import ../../../policy/globals.nix).tailnet.suffix;
    };

    composition = {
      extraModules = [
        inputs.disko.nixosModules.disko
        inputs.sops-nix.nixosModules.sops
      ];

      aspects = [
        aspects.provenance
        aspects.oci-images
        aspects.fleet-packages
        aspects.web-policy
        # Stage 7 placement aspects (D-053): one selection per deployed
        # product/platform capability; no host imports its implementation.
        aspects.dj
        aspects.music
        aspects.omniroute
        aspects.postgres
        # Foundation aspects (FND-1): selection is enablement.
        aspects.base
        aspects.shell
        aspects.networking
        aspects.tailscale
        aspects.notify
        # Operational aspects: selection is enablement.
        aspects.state-backups
        aspects.cache-publisher
        aspects.internal-contracts
        aspects.builder-access
        aspects.observability-agent
      ];

      fragments = [ ./_nixos.nix ];
    };
  };
}
