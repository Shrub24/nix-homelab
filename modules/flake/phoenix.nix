# Phoenix deployment aspect (dendritic Stage 7, D-053). Published from this
# discovered contributor and selected only on `oci-melb-1` (S7-2). Selection
# supplies the collector's existing top-level enablement; image policy and
# data paths keep their leaf defaults.
{ ... }:
{
  flake.modules.nixos.phoenix = {
    imports = [ ../services/phoenix.nix ];

    # Selecting this aspect is the collector's top-level enablement.
    services.phoenix.enable = true;
  };
}
