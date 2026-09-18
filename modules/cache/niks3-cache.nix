# Niks3 cache-server deployment aspect (dendritic Stage 7, D-053). Published
# from this discovered contributor and selected only on `oci-melb-1` (S7-2).
# Selection supplies the server leaf's existing top-level enablement; the
# host/API-token and service secret sources stay explicit host variants.
#
# This aspect is the binary-cache server only; the fleet-wide cache consumer,
# upload client, and backups behavior belong to the `backups` aspect and are
# not activated from here.
{ ... }:
{
  flake.modules.nixos.niks3-cache = {
    imports = [ ../services/niks3.nix ];

    # Selecting this aspect is the server's top-level enablement.
    services.niks3-cache.enable = true;
  };
}
