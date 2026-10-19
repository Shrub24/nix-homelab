# Host entry point: the canonical typed record (deferred NixOS composition)
# whose identity derives from nix-fleet's fleet inventory. The NixOS composition
# stays host-private in `_nixos.nix` and its `_disko-two-disk.nix` sibling, so a
# host assembly can never be selected as a public aspect.
{
  config,
  inputs,
  ...
}:
let
  aspects = config.flake.modules.nixos;
  identity = config.fleet.hosts.home-forge;
in
{
  # Canonical machine identity (target system, Tailscale hostname, host key)
  # lives in nix-fleet's fleet inventory; this record derives from it and
  # declares only what is ours — composition and disks.
  nixos.hosts.home-forge = {
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
        # Selection is enablement; no host imports an implementation.
        aspects.dj
        aspects.music
        aspects.omniroute
        aspects.postgres
        # The fleet's model gateway, placed here as well as on oci-melb-1 so
        # this host's inference consumers dial loopback instead of the tailnet.
        aspects.bifrost
        # Knowledge domain (search, agent memory, documentation index).
        aspects.degoog
        aspects.hindsight
        aspects.docs-mcp
        # Home automation: the upstream container, host-networked for discovery.
        aspects.home-assistant
        # Foundation aspects (FND-1): selection is enablement.
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
        # Telemetry: the contract's vocabulary plus our fleet policy, then the
        # signals this host ships. It is the gateway for admitted OTLP signals,
        # so it also composes the OTLP lane.
        aspects.telemetry
        aspects.telemetry-metrics
        aspects.telemetry-logs
        aspects.telemetry-otlp
        aspects.node-exporter
        aspects.container-env
        # Observability store: VictoriaMetrics/VictoriaLogs/VictoriaTraces
        # plus Grafana, placed on the host with the disks for it.
        aspects.victoria
        # LLM observability backends, colocated with the telemetry stores.
        aspects.langfuse
        aspects.latitude
      ];

      fragments = [ ./_nixos.nix ];
    };
  };
}
