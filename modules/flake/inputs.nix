# Flake inputs, declared in the tree. nix-fleet owns the pins both repositories share
# (nixpkgs, flake-parts, import-tree, sops-nix, niks3), which this repository follows.
{ lib, ... }:
{
  flake-file.inputs = {
    flake-file.url = "github:denful/flake-file";
    nix-fleet.url = "github:Shrub24/nix-fleet";

    # `url = lib.mkForce ""` clears the URL the dendritic preset defaults these to; flake-file renders
    # a URL-less input as a pure follows alias, and an input may not carry both a URL and a follows.
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
    # Formatting: the mode emits the `checks.<system>.treefmt` gate the fleet's
    # validator builds, from the settings declared in `modules/flake/treefmt.nix`.
    treefmt-nix.follows = "nix-fleet/treefmt-nix";

    # Temporary: paperless 3.3.3 has no aarch64 build anywhere (its test suite fails on Linux, and
    # Hydra aborts the derivation on log volume before finishing), so paperless comes from the
    # revision whose build the fleet already runs. Remove once a newer paperless substitutes or
    # builds; docs/plan.md carries the trigger.
    nixpkgs-paperless.url = "github:NixOS/nixpkgs/fe13242281a67641c0102cdb1087f0ebe586c7df";

    # Deployment and host-recovery dependencies stay fleet-owned.
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    # degoog's dependency expression is generated from its Bun lockfile; the
    # generator is ours so a degoog bump cannot change the artifact's shape.
    # Pinned to a release, like degoog: Renovate's custom regex manager tracks
    # the tag, and a bump that changes the generated output is then visible as a
    # failing `check-degoog-bun-deps` rather than a silent divergence.
    bun2nix.url = "github:nix-community/bun2nix/2.1.2";
    bun2nix.inputs.nixpkgs.follows = "nixpkgs";
    bun2nix.inputs.flake-parts.follows = "flake-parts";
    bun2nix.inputs.treefmt-nix.follows = "nix-fleet/treefmt-nix";
    traktor-m3u-sync.url = "github:Shrub24/traktor-m3u-sync";
    traktor-m3u-sync.inputs.nixpkgs.follows = "nixpkgs";
    traktor-m3u-sync.inputs.flake-parts.follows = "flake-parts";
    traktor-m3u-sync.inputs.treefmt-nix.follows = "nix-fleet/treefmt-nix";

    authentik-nix.url = "github:nix-community/authentik-nix";

  };
}
