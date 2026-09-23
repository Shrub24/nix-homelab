# Host entry point: the canonical typed record (deferred NixOS composition,
# deploy facts) whose identity derives from nix-fleet's fleet inventory. The
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
  # Canonical machine identity (target system, Tailscale hostname, host key)
  # lives in nix-fleet's fleet inventory; this record derives from it and
  # declares only what is ours — composition, admin runtime, deploy facts.
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
