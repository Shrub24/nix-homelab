# Karakeep deployment aspect (dendritic Stage 7, D-053). Published from this
# discovered contributor and selected only on `oci-melb-1` (S7-2). Selection
# supplies the pod's existing top-level enablement; OIDC wiring, the S3 asset
# store toggle, and both secret sources stay explicit host variants.
{ ... }:
{
  flake.modules.nixos.karakeep = {
    imports = [ ../services/karakeep.nix ];

    # Selecting this aspect is the application's top-level enablement.
    services.karakeep-pod.enable = true;
  };
}
