# Host entry point: the typed record whose identity derives from the fleet inventory, with
# the NixOS composition host-private beside it.
{
  config,
  inputs,
  ...
}:
let
  aspects = config.flake.modules.nixos;
  identity = config.fleet.hosts.la-admin-1;
in
{
  # Identity comes from the inventory; this record declares only composition, admin runtime
  # and deploy facts.
  nixos.hosts.la-admin-1 = {
    system = identity.system;

    tailscale = {
      hostname = identity.tailscale.hostname;
      tailnetSuffix = (import ../../../policy/globals.nix).tailnet.suffix;
    };

    composition = {
      extraModules = [ inputs.sops-nix.nixosModules.sops ];

      aspects = [
        aspects.provenance
        aspects.oci-images
        aspects.fleet-packages
        aspects.web-policy
        # Selection is enablement; no host imports an implementation.
        aspects.ingress
        aspects.push-server
        aspects.vaultwarden
        aspects.gatus
        aspects.beszel
        aspects.homepage
        aspects.webhook
        # Secrets install through a systemd unit that consumers order after.
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
      ];

      fragments = [ ./_nixos.nix ];
    };
  };
}
