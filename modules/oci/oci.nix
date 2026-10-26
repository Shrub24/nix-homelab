# OCI platform defaults (serial console, GRUB, boot) plus this host's podman prune and
# its notification registration.
{ ... }:
{
  flake.modules.nixos.oci =
    { ... }:
    {
      config = {
        boot.loader.grub.devices = [ "/dev/sda" ];

        # Keep OCI serial-console recovery available after reboot.
        boot.kernelParams = [ "console=ttyAMA0,115200n8" ];

        systemd.services."serial-getty@ttyAMA0" = {
          enable = true;
          wantedBy = [ "multi-user.target" ];
        };
      };
    };
}
