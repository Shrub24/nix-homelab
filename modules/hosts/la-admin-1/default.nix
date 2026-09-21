# Host entry point: the canonical typed record (target system, Tailscale
# identity, deferred NixOS composition, deploy facts). The NixOS composition
# stays host-private in `_nixos.nix` and its `_admin-runtime.nix` sibling, so a
# host assembly can never be selected as a public aspect.
{
  config,
  inputs,
  ...
}:
let
  aspects = config.flake.modules.nixos;
in
{
  nixos.hosts.la-admin-1 = {
    system = "x86_64-linux";

    tailscale = {
      hostname = "la-admin-1";
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
