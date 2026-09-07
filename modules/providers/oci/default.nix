_: {
  boot.loader.grub.devices = [ "/dev/sda" ];

  # Keep OCI serial-console recovery available after reboot.
  # Provider-specific console wiring intentionally lives here.
  boot.kernelParams = [ "console=ttyAMA0,115200n8" ];

  systemd.services."serial-getty@ttyAMA0" = {
    enable = true;
    wantedBy = [ "multi-user.target" ];
  };
}
