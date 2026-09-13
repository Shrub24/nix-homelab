# Identity-provider deployment aspect (dendritic Stage 7, D-053). Published
# from this discovered contributor and selected only on `la-admin-1` (S7-2).
# It owns the Kanidm server/provisioning composition, the Kanidm top-level
# enablement, and the canonical OIDC provider URL consumed by
# `identity-client`.
#
# Mandatory policy co-selection (D-050/D-053): selecting this aspect is the
# Kanidm capability's top-level enablement, but `la-admin-1` must also select
# `admin-hub` and `identity-client`. The coupling is config reads only, never
# imports (S7-2/S7-3):
#   * `applications.admin` (owned by `admin-hub`) supplies `policyServices`,
#     `dataRoot`, and the identity secret sources read below;
#   * `services.identity.oidc` (owned by `identity-client`) owns the
#     `providerUrl` option this aspect sets.
# A lone selection therefore fails evaluation loudly with the missing sibling
# option namespace rather than silently reconfiguring a sibling.
{ ... }:
{
  flake.modules.nixos.identity-provider =
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.applications.admin;
    in
    {
      imports = [ ../services/admin/kanidm.nix ];

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            services.identity.oidc.providerUrl = cfg.policyServices."kanidm-admin".publicUrl;
            # Selecting this aspect is the Kanidm capability's top-level
            # enablement (D-053); declared outside the enable check below, which
            # reads it.
            services.admin.kanidm.enable = lib.mkDefault true;
          }

          # Kanidm data/app URL/TLS composition.
          (lib.mkIf config.services.admin.kanidm.enable {
            services.admin.kanidm = {
              dataDir = "${cfg.dataRoot}/kanidm";
              appUrl = cfg.policyServices."kanidm-admin".publicUrl;
              tlsChainFile = "/var/lib/acme/${cfg.policyServices."kanidm-admin".primaryDomain}/fullchain.pem";
              tlsKeyFile = "/var/lib/acme/${cfg.policyServices."kanidm-admin".primaryDomain}/key.pem";
              tlsReaderGroups = [ "caddy" ];
            };
          })
        ]
      );
    };
}
