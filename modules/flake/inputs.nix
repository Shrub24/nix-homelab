# Flake inputs, declared in the tree instead of a hand-written manifest.
# nix-fleet is the authority for the pins both repositories share: it owns
# nixpkgs, flake-parts, import-tree, sops-nix and niks3, and this repository
# follows those inputs rather than carrying its own copies, so one nix-fleet
# revision moves the shared baseline everywhere.
{ lib, ... }:
{
  flake-file.inputs = {
    flake-file.url = "github:denful/flake-file";
    nix-fleet.url = "github:Shrub24/nix-fleet";

    # `url = lib.mkForce ""` clears the URL the dendritic preset defaults
    # these to; flake-file renders a URL-less input as a pure follows alias,
    # and an input may not carry both a URL and a follows.
    nixpkgs = {
      url = lib.mkForce "";
      follows = "nix-fleet/nixpkgs";
    };
    flake-parts = {
      url = lib.mkForce "";
      follows = "nix-fleet/flake-parts";
    };
    import-tree = {
      url = lib.mkForce "";
      follows = "nix-fleet/import-tree";
    };
    sops-nix.follows = "nix-fleet/sops-nix";
    niks3.follows = "nix-fleet/niks3";

    # Deployment and host-recovery dependencies stay fleet-owned.
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    traktor-m3u-sync.url = "github:Shrub24/traktor-m3u-sync";
    traktor-m3u-sync.inputs.nixpkgs.follows = "nixpkgs";
  };
}
