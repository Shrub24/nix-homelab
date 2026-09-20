# Paperless deployment aspect (dendritic Stage 7, D-053). Published from this
# discovered contributor and selected only on `oci-melb-1` (S7-2). The
# Paperless service leaf (including the GPT/docling composition) is the
# intrinsic implementation and selection supplies the existing top-level
# enablement. Host-scoped variants stay explicit: data root, secret sources,
# catalog-derived OIDC wiring, the LLM model aliases, and the docling instance
# toggles.
{ ... }:
{
  flake.modules.nixos.paperless = {

    # Selecting this aspect is the application's top-level enablement.
    services.paperless.enable = true;
  };
}
