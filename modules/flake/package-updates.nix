# The repository's package-update surface: nix-fleet's published
# package-updates flake module (a typed registry plus one batch app over the
# shared runner) plus this repository's registration.
#
# The interface, per nix-fleet docs/contracts/package-updates.md:
#   nix run .#update             interactive picker over flake inputs and package updates
#   nix run .#update-packages    batch, or the named packages; -- --check is the cheap release check
#
# `windows-dj-setup` is the only package this repository owns. Every other
# `packages.<system>` entry is derived from an input (deploy-rs, niks3,
# sops-bootstrap, bifrost, bifrost-voyage-plugin), a deploy profile (host-*), or
# nix-fleet's own CI helper, so none of them is a second writer.
{ inputs, ... }:
{
  imports = [ inputs.nix-fleet.flakeModules.packageUpdates ];

  perSystem.packageUpdates.packages = [ "windows-dj-setup" ];
}
