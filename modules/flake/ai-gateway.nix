# Bifrost AI-gateway deployment aspect (dendritic Stage 7, D-053). Published
# from this discovered contributor and selected only on `oci-melb-1` (S7-2).
# Selection supplies the gateway's existing top-level enablement; the data
# root, the policy config file, and the service secret source stay explicit
# host variants.
{ ... }:
{
  flake.modules.nixos.ai-gateway = {
    imports = [ ../services/bifrost-gateway.nix ];

    # Selecting this aspect is the gateway's top-level enablement.
    services.bifrost-gateway.enable = true;
  };
}
