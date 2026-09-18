# OCI platform aspect (dendritic Stage 7, D-053). Published from this
# discovered contributor and selected only on `oci-melb-1`; the provider
# implementation is a private leaf beside its owner (S7-3/S7-5). Selecting the
# aspect is the host's provider-placement statement; the leaf carries the OCI
# serial console, GRUB device, and provider boot defaults unchanged.
{ ... }:
{
  flake.modules.nixos.oci = {
    imports = [ ./_oci/default.nix ];
  };
}
