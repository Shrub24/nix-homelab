# Host entry point: the canonical typed record (target system, Tailscale
# identity, deferred NixOS composition). The NixOS composition stays
# host-private in `_nixos.nix` and its `_disko-two-disk.nix` sibling, so a host
# assembly can never be selected as a public aspect.
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
