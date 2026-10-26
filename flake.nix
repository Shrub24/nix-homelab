# DO-NOT-EDIT. This file was auto-generated using github:denful/flake-file.
# Use `nix run .#write-flake` to regenerate it.
{
  description = "Modular NixOS fleet infrastructure";

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);

  inputs = {
    authentik-nix.url = "github:nix-community/authentik-nix";
    bun2nix = {
      url = "github:nix-community/bun2nix/2.1.2";
      inputs = {
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
        treefmt-nix.follows = "nix-fleet/treefmt-nix";
      };
    };
    degoog = {
      url = "github:degoog-org/degoog/1.1.0";
      inputs = {
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
      };
    };
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
    nixpkgs-paperless.url = "github:NixOS/nixpkgs/fe13242281a67641c0102cdb1087f0ebe586c7df";
    sops-nix.follows = "nix-fleet/sops-nix";
    traktor-m3u-sync = {
      url = "github:Shrub24/traktor-m3u-sync";
      inputs = {
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
        treefmt-nix.follows = "nix-fleet/treefmt-nix";
      };
    };
    treefmt-nix.follows = "nix-fleet/treefmt-nix";
  };
}
