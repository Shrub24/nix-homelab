# OCI platform aspect (dendritic Stage 7, D-053). Published from this
# discovered contributor and selected only on `oci-melb-1`. Selecting the
# aspect is the host's provider-placement statement; the OCI serial console,
# GRUB device, and provider boot defaults are nested in the publication
# itself, so there is no private leaf.
{ ... }:
{
  flake.modules.nixos.oci = {
    boot.loader.grub.devices = [ "/dev/sda" ];

    # Keep OCI serial-console recovery available after reboot.
    # Provider-specific console wiring intentionally lives here.
    boot.kernelParams = [ "console=ttyAMA0,115200n8" ];

    systemd.services."serial-getty@ttyAMA0" = {
      enable = true;
      wantedBy = [ "multi-user.target" ];
    };
  };
}
