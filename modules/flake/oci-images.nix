# Typed OCI image policy at the NixOS module boundary (DS-4): services read
# config.repo.ociImages.<name> instead of an ociImages flake argument.
{ lib, ... }:
let
  ociImagesPolicy = import ../../policy/oci-images.nix;
in
{
  flake.modules.nixos.oci-images =
    { ... }:
    {
      options.repo.ociImages = lib.mkOption {
        type = lib.types.attrs;
        readOnly = true;
        description = "Canonical OCI image refs from policy/oci-images.nix.";
      };

      config.repo.ociImages = ociImagesPolicy;
    };
}
