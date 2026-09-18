# Webhook deployment aspect (dendritic Stage 7, D-053; self-contained placement aspect since D-054). Published from this
# discovered contributor and selected only on `la-admin-1` (explicit
# `aspects.webhook`). Selecting the aspect imports the Webhook leaf and owns
# its enablement; the runtime composition — the loopback bind address and the
# upstream `services.webhook` health hook — stays in the leaf.
#
# Dependency direction (decouple-identity-admin-capabilities 3.2): the aspect
# and its leaf consume no web policy, secret source, or runtime path, and read
# no `applications.admin` namespace. Nothing in-repo posts to Webhook; the
# retained `webhook-admin` policy route serves external/manual callers only,
# so this aspect has no named dependency contract and emits no throw.
{ ... }:
{
  flake.modules.nixos.webhook =
    { ... }:
    {
      imports = [ ../services/admin/webhook.nix ];

      config = {
        # Selecting this aspect is the capability's top-level enablement.
        services.admin.webhook.enable = true;
      };
    };
}
