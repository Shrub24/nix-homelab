# OCI platform aspect: selecting it is the host's provider-placement statement;
# the serial console, GRUB device, and provider boot defaults are nested in the
# publication itself, so there is no private leaf.
_: {
  flake.modules.nixos.oci = {
    boot.loader.grub.devices = [ "/dev/sda" ];

    # Keep OCI serial-console recovery available after reboot.
    boot.kernelParams = [ "console=ttyAMA0,115200n8" ];

    systemd.services."serial-getty@ttyAMA0" = {
      enable = true;
      wantedBy = [ "multi-user.target" ];
    };
  };
}
