# DO-NOT-EDIT. This file was auto-generated using github:denful/flake-file.
# Use `nix run .#write-flake` to regenerate it.
{
  description = "Modular NixOS fleet infrastructure";

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);

  inputs = {
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-file.url = "github:denful/flake-file";
    flake-parts = {
      follows = "nix-fleet/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    import-tree.follows = "nix-fleet/import-tree";
    niks3.follows = "nix-fleet/niks3";
    nix-fleet.url = "github:Shrub24/nix-fleet";
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.follows = "nix-fleet/nixpkgs";
    sops-nix.follows = "nix-fleet/sops-nix";
    traktor-m3u-sync = {
      url = "github:Shrub24/traktor-m3u-sync";
      inputs = {
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
        treefmt-nix.follows = "nix-fleet/treefmt-nix";
      };
    };
  };
}
