# Repository provenance (configurationRevision, /etc/nixos-source) is owned by
# the flake-level provenance aspect, not by this leaf (design DS-4).
{
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
    trusted-users = [
      "root"
      "dev"
    ];
  };

  time.timeZone = "UTC";

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  boot.loader.efi.canTouchEfiVariables = false;

  security.sudo.wheelNeedsPassword = false;
}
