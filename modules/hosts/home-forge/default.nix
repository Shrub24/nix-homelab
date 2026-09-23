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
  };
}
