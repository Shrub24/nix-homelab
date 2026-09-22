# Host entry point: the fleet-registry machine identity plus the canonical typed
# record (deferred NixOS composition) that derives from it. The NixOS composition
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
  # Machine identity for the fleet registry (nix-fleet's hosts contract): who
  # this host is, not what it runs. The host key was read from the host's own
  # /etc/ssh/ssh_host_ed25519_key.pub
  # (SHA256:6acEmfUj8pcHR65uDUKuLtaaRRUUot+Af5IOPvoByPU).
  fleet.hosts.home-forge = {
    system = "x86_64-linux";
    tailscale.hostname = "home-forge";
    hostNames = [ "home-forge" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILre5rGGN4yjhV8XJpREgl+BRdru24t8NZgHTvpgouKf root@home-forge";
  };

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
