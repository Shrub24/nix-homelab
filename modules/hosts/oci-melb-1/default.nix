# Host entry point: the fleet-registry machine identity plus the canonical typed
# record (deferred NixOS composition, reimage facts) that derives from it. The
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
  # Machine identity for the fleet registry (nix-fleet's hosts contract): who
  # this host is, not what it runs. The host key was read from the host's own
  # /etc/ssh/ssh_host_ed25519_key.pub
  # (SHA256:OKw68XDI4NwWHHuoauvjBsTdwaUCrDrPKbIFKEY+SXE).
  fleet.hosts.oci-melb-1 = {
    system = "aarch64-linux";
    tailscale.hostname = "oci-melb-1";
    hostNames = [ "oci-melb-1" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC8NW1V+x+tvbwzPMEcGRlK2V1XXAuDgdJ2dUQssiWaC root@oci-melb-1";
  };

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
        aspects.phoenix
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
