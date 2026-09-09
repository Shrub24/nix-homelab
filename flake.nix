{
  description = "Modular NixOS fleet infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";
    niks3.url = "github:Mic92/niks3";
    niks3.inputs.nixpkgs.follows = "nixpkgs";
    traktor-m3u-sync.url = "github:Shrub24/traktor-m3u-sync";
    traktor-m3u-sync.inputs.nixpkgs.follows = "nixpkgs";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    import-tree.url = "github:denful/import-tree";
  };

  outputs =
    inputs:
    let
      inherit (inputs.nixpkgs) lib;

      # Temporary boundary (design DS-1): directories under modules/ that still
      # hold plain NixOS leaves not yet converted to aspect contributors. The
      # enumerated list is inspectable in modules/flake/_unconverted-nixos-dirs.nix;
      # entries are removed as conversion progresses. A leaked leaf fails
      # evaluation loudly; there is no fallback blanket-import root.
      unconvertedNixosDirs = import ./modules/flake/_unconverted-nixos-dirs.nix;
      discovery = inputs.import-tree.filterNot (
        relPath: lib.any (dir: lib.hasPrefix "/${dir}/" relPath) unconvertedNixosDirs
      ) ./modules;
    in
    inputs.flake-parts.lib.mkFlake { inherit inputs; } discovery;
}
