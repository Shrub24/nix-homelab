# Host entry point: the fleet-registry machine identity plus the canonical typed
# record (deferred NixOS composition, deploy facts) that derives from it. The
# NixOS composition stays host-private in `_nixos.nix` and its `_admin-runtime.nix`
# sibling, so a host assembly can never be selected as a public aspect.
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
  # Machine identity for the fleet registry (nix-fleet's hosts contract): who
  # this host is, not what it runs. The host key was read from the host's own
  # /etc/ssh/ssh_host_ed25519_key.pub
  # (SHA256:g71ri368dh+EkeJgXrHmMsrxlkwHI2T9G8rFD+G6fWw).
  fleet.hosts.la-admin-1 = {
    system = "x86_64-linux";
    tailscale.hostname = "la-admin-1";
    hostNames = [ "la-admin-1" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINNXbGpZyizRCUVdjz35hFTmoWLgM8TPwGbQjCvrrcER root@nixos";
  };

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
        aspects.kanidm-host-auth
        # Selection is enablement; no host imports an implementation.
        aspects.ingress
        aspects.push-server
        aspects.identity-provider
        aspects.vaultwarden
        aspects.gatus
        aspects.beszel
        aspects.homepage
        aspects.webhook
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
