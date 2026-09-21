# OCI platform aspect: selecting it is the host's provider-placement statement;
# the serial console, GRUB device, and provider boot defaults are nested in the
# publication itself, so there is no private leaf. It also owns this host's
# podman storage prune and its notification registration.
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

        # nixpkgs' podman module defines the `podman-prune` unit unconditionally
        # (its ExecStart is not gated on autoPrune.enable), so nix-fleet's
        # `podman-prune` aspect cannot coexist with it. The platform unit is the
        # mechanism here: nixpkgs owns the unit and timer, our retention flags
        # match what this host pruned before, and the failure event is registered
        # below through the notify contract.
        virtualisation.podman.autoPrune = {
          enable = true;
          dates = "weekly";
          flags = [
            "--all"
            "--force"
            "--volumes"
          ];
        };

        services.notify.events."podman-prune".failure = { };
      };
    };
}
