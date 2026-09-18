# Beszel hub deployment aspect (dendritic Stage 7, D-053; self-contained placement aspect since D-054). Published from this
# discovered contributor and selected only on `la-admin-1` (explicit
# `aspects.beszel`). Selecting the aspect imports the Beszel leaf and owns its
# enablement; the runtime composition — policy public URL, origin host/port,
# and the state-backups registration — stays in the leaf.
#
# Dependency direction (decouple-identity-admin-capabilities 3.2): the aspect
# and its leaf consume only the canonical web policy
# (`repo.web.currentHost.services`) and never read the
# `applications.admin` option namespace.
#
# Named dependency failure (feature-topology/admin-module-structure): a
# selection without the canonical `beszel-admin` web-policy route must fail
# through the leaf's named throw identifying the missing contract, not a raw
# missing-attribute error.
{ ... }:
{
  flake.modules.nixos.beszel =
    { ... }:
    {
      imports = [ ../services/admin/beszel.nix ];

      config = {
        # Selecting this aspect is the capability's top-level enablement.
        services.admin.beszel.enable = true;
      };
    };
}
