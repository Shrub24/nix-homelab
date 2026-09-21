# Host entry point: the canonical typed record (target system, Tailscale
# identity, deferred NixOS composition, reimage facts). The NixOS composition
# stays host-private in `_nixos.nix` and its `_disko-*.nix` / `_cockpit-auth.nix`
# siblings, so a host assembly can never be selected as a public aspect.
{
  config,
  inputs,
  ...
}:
let
  aspects = config.flake.modules.nixos;
in
{
  nixos.hosts.oci-melb-1 = {
    system = "aarch64-linux";

    tailscale = {
      hostname = "oci-melb-1";
      tailnetSuffix = (import ../../../policy/globals.nix).tailnet.suffix;
    };

    composition = {
      extraModules = [
        inputs.disko.nixosModules.disko
        inputs.sops-nix.nixosModules.sops
        inputs.niks3.nixosModules.niks3
      ];

      aspects = [
        aspects.provenance
        aspects.oci-images
        aspects.fleet-packages
        aspects.web-policy
        aspects.kanidm-host-auth
        # Selection is enablement; no host imports an implementation.
        aspects.oci
        aspects.edge
        aspects.cockpit
        aspects.paperless
        aspects.postgres
        aspects.ai-gateway
        aspects.karakeep
        aspects.niks3-cache
        aspects.phoenix
        aspects.base
        aspects.shell
        aspects.networking
        aspects.tailscale
        aspects.notify
        aspects.state-backups
        aspects.cache-publisher
        aspects.internal-contracts
        aspects.builder-access
        aspects.observability-agent
      ];

      fragments = [ ./_nixos.nix ];
    };

    # Reimage-only facts; hostName and flake come from the record key.
    bootstrap = {
      bootstrapUser = "ubuntu";
      bootstrapDisk = "/dev/sda";
      mediaDisk = "/dev/sdb";
      rootPartitionSize = "20G";
      dataRoot = "/srv/data";
    };
  };
}
