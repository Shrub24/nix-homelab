# Host entry point: the canonical typed record (deferred NixOS composition,
# reimage facts) whose identity derives from nix-fleet's fleet inventory. The
# NixOS composition stays host-private in `_nixos.nix` and its `_disko-*.nix` /
# `_cockpit-auth.nix` siblings, so a host assembly can never be selected as a
# public aspect.
{
  config,
  inputs,
  ...
}:
let
  aspects = config.flake.modules.nixos;
  identity = config.fleet.hosts.oci-melb-1;
in
{
  # Canonical machine identity (target system, Tailscale hostname, host key)
  # lives in nix-fleet's fleet inventory; this record derives from it and
  # declares only what is ours — composition, disks, reimage facts.
  nixos.hosts.oci-melb-1 = {
    system = identity.system;

    tailscale = {
      hostname = identity.tailscale.hostname;
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
        aspects.kanidm-host-auth
        # Selection is enablement; no host imports an implementation.
        aspects.oci
        aspects.ingress
        aspects.cockpit
        aspects.paperless
        aspects.postgres
        aspects.bifrost
        aspects.karakeep
        aspects.niks3-cache
        aspects.langfuse
        aspects.base
        aspects.shell
        aspects.networking
        aspects.tailscale
        aspects.notify
        aspects.state-backups
        aspects.cache-publisher
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
