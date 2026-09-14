# Homepage dashboard deployment aspect (dendritic Stage 7, D-053). Published
# from this discovered contributor and selected only on `la-admin-1` (explicit
# `aspects.homepage`). Selecting the aspect imports the Homepage leaf and owns
# its enablement; the runtime composition — policy origin host/port, the
# 8-secret map, the `homepage-auth.env` template, and the catalog-derived
# dashboard data — stays in the leaf.
#
# Dependency direction (decouple-identity-admin-capabilities 3.2): the aspect
# and its leaf consume only the canonical web policy
# (`repo.web.currentHost.services`) and never read the
# `applications.admin` option namespace. The host keeps only the
# host-scoped secret source binding (`services.admin.homepage.secretFiles.host`).
#
# Named dependency failure (feature-topology/admin-module-structure): a
# selection without the canonical `admin-homepage` web-policy route must fail
# through the leaf's named throw identifying the missing contract, not a raw
# missing-attribute error.
{ ... }:
{
  flake.modules.nixos.homepage =
    { ... }:
    {
      imports = [ ../services/admin/homepage/default.nix ];

      config = {
        # Selecting this aspect is the capability's top-level enablement.
        services.admin.homepage.enable = true;
      };
    };
}
