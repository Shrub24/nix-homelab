# Systemd secret-activation aspect (bridge to nix-fleet's fleet policy).
#
# nix-fleet owns the policy (`sops-systemd-activation`): the
# `sops.useSystemdActivation` default and the assertion that keeps a consumer
# from dropping back to the deprecated activation-script install. This
# contributor publishes the fleet aspect name, so host records select the same
# name whether the policy is realised here or upstream, and it adds no
# convention of its own — sops-nix itself stays a host import.
{ inputs, ... }:
{
  flake.modules.nixos.sops-systemd-activation = {
    imports = [ inputs.nix-fleet.modules.nixos.sops-systemd-activation ];
  };
}
