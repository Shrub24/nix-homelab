# Bridge to nix-fleet's sops systemd-activation policy: publishes the aspect name and adds
# no convention of its own. sops-nix itself stays a host import.
{ inputs, ... }:
{
  flake.modules.nixos.sops-systemd-activation = {
    imports = [ inputs.nix-fleet.modules.nixos.sops-systemd-activation ];
  };
}
