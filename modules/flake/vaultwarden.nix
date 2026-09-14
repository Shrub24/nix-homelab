# Vaultwarden deployment aspect (dendritic Stage 7, D-053). Published from this
# discovered contributor and selected only on `la-admin-1` (explicit
# `aspects.vaultwarden`). Selecting the aspect imports the Vaultwarden leaf and
# owns its enablement; the runtime composition stays in the leaf. The runtime
# data path stays the leaf default (`/srv/data/vaultwarden`).
#
# Dependency direction (decouple-identity-admin-capabilities 3.1): the aspect
# and its leaf consume only public contracts — the canonical web policy
# (`repo.web.currentHost.services."vaultwarden-admin"`) — and never read the
# `applications.admin` namespace. Vaultwarden has no OIDC, no Kanidm, and no
# Tailscale serve unit (the route is direct edge-proxied). The host keeps only
# the host-scoped secret source (`services.admin.vaultwarden.secretFiles.host`).
#
# Named dependency failure (feature-topology/admin-module-structure): a
# selection without the canonical web-policy route must fail through the
# leaf's named throw identifying the missing contract, not a raw
# missing-attribute error.
{ ... }:
{
  flake.modules.nixos.vaultwarden =
    { ... }:
    {
      imports = [ ../services/admin/vaultwarden.nix ];

      config = {
        # Selecting this aspect is the capability's top-level enablement.
        services.admin.vaultwarden.enable = true;
      };
    };
}
