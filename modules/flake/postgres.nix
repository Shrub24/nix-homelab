# Shared PostgreSQL deployment aspect (dendritic Stage 7, D-053). Published
# from this discovered contributor and selected only on `oci-melb-1` (S7-2).
# Selection supplies the existing top-level enablement of the shared platform
# substrate; the consumer-role enables (`niks3`, `paperless`, `audiomuse`,
# `litellm`) and the conventional secret file stay explicit host variants.
{ ... }:
{
  flake.modules.nixos.postgres = {
    imports = [ ../services/postgres-shared.nix ];

    # Selecting this aspect is the substrate's top-level enablement.
    services.postgres-shared.enable = true;
  };
}
