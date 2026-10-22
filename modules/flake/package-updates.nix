# The repository's package-update surface: nix-fleet's published
# package-updates flake module (a typed registry plus one batch app over the
# shared runner) plus this repository's registration.
#
# The interface, per nix-fleet docs/contracts/package-updates.md:
#   nix run .#update             interactive picker over flake inputs and package updates
#   nix run .#update-packages    batch, or the named packages; -- --check is the cheap release check
#
# `windows-dj-setup`, `geopulse` and `degoog` are the packages this repository
# owns. GeoPulse's backend and frontend build from one upstream pin, so the batch
# dispatches `geopulse` to its own coupled updater (pkgs/geopulse/update.py) and
# the two halves stay derived outputs. `degoog`'s pin is its flake input, so its
# updater only regenerates the dependency expression that input's lockfile
# produces. Every other `packages.<system>` entry is
# derived from an input (deploy-rs, niks3, sops-bootstrap, bifrost,
# bifrost-voyage-plugin), a deploy profile (host-*), or nix-fleet's own CI
# helper, so none of them is a second writer.
{ inputs, ... }:
{
  imports = [ inputs.nix-fleet.flakeModules.packageUpdates ];

  perSystem.packageUpdates.packages = [
    "degoog"
    "geopulse"
    "windows-dj-setup"
  ];
}
