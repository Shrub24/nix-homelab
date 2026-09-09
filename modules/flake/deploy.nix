# deploy-rs wiring (DS-4, DS-6). lib/deploy/hosts.nix remains the physical
# topology SSOT (edgeHost, deployOrder, ssh users, remote-build flags); node
# profiles are built from the materialized configurations directly, replacing
# the old self.nixosConfigurations dereference.
top@{ inputs, ... }:
let
  deployTopology = import ../../lib/deploy/hosts.nix;

  deployConfig = import ../../lib/deploy {
    inherit (inputs) nixpkgs deploy-rs;
    nixosConfigurations = top.config.flake.nixosConfigurations;
    inherit (deployTopology) nodes;
  };
in
{
  flake = {
    inherit (deployConfig) deploy;
    deployHosts = deployTopology;
  };

  perSystem =
    { system, ... }:
    {
      checks = inputs.deploy-rs.lib.${system}.deployChecks top.config.flake.deploy;
    };
}
