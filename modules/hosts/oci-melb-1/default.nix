# Host entry point: the typed record whose identity derives from the fleet inventory, with
# the NixOS composition host-private beside it.
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
  # Identity comes from the inventory; this record declares only composition, disks and
  # reimage facts.
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
        aspects.paperless
        aspects.postgres
        aspects.bifrost
        aspects.karakeep
        aspects.actual
        aspects.memos
        aspects.tududi
        aspects.inbox-zero
        aspects.homarr
        aspects.geopulse
        aspects.niks3-cache
        aspects.sops-systemd-activation
        aspects.base
        aspects.shell
        aspects.networking
        aspects.tailscale
        aspects.notify
        aspects.state-backups
        aspects.cache-publisher
        aspects.builder-access
        aspects.build-account
        aspects.observability-agent
        # Telemetry: the contract's vocabulary plus our fleet policy, then the signals this host ships
        # — metrics and logs; OTLP is admitted by the gateway host, not here.
        aspects.telemetry
        aspects.telemetry-metrics
        aspects.telemetry-logs
        aspects.node-exporter
        aspects.containers
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
