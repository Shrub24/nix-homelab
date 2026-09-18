# deploy-rs wiring (DS-4, DS-6). lib/deploy/hosts.nix remains the physical
# topology SSOT (edgeHost, deployOrder, ssh users, remote-build flags); node
# profiles are built from the materialized configurations directly, replacing
# the old self.nixosConfigurations dereference.
#
# Stage 8 task 3.1 (HIC-3, "reference, do not merge"): every host reference in
# the deploy metadata — node keys, edgeHost, and deployOrder entries — must name
# a declared canonical host ID (the keys of the discovered `nixos.hosts`
# records), and every node's `system` must agree with that record. Both fail
# closed with named errors, so a drifted deploy topology cannot silently produce
# a deploy output. The topology keeps owning its own physical facts; they are
# never merged into the host records.
top@{ inputs, lib, ... }:
let
  deployTopology = import ../../lib/deploy/hosts.nix;

  references =
    builtins.attrNames deployTopology.nodes
    ++ [ deployTopology.edgeHost ]
    ++ deployTopology.deployOrder;

  unknownReferences = lib.filter (name: !(top.config.nixos.hosts ? ${name})) (lib.unique references);

  # The topology keeps owning its own physical facts, so a node's `system` is
  # not derived from the host record — but a disagreement between the two makes
  # deploy-rs activate the wrong architecture, so it fails closed as well.
  systemDrift =
    lib.mapAttrsToList
      (
        name: node:
        "deploy: node '${name}' declares system '${node.system}' but canonical host record declares '${
          top.config.nixos.hosts.${name}.system
        }'"
      )
      (
        lib.filterAttrs (
          name: node: top.config.nixos.hosts ? ${name} && node.system != top.config.nixos.hosts.${name}.system
        ) deployTopology.nodes
      );

  # One named error per drift site, so a failing evaluation reports every drifted
  # reference (node key / edgeHost / deployOrder) instead of only the first.
  # Unknown references dominate: the system check reads the canonical records,
  # so it is only forced once every reference names a declared host.
  checkedDeployTopology =
    lib.throwIf (unknownReferences != [ ])
      (lib.concatMapStringsSep "; " (
        name: "deploy: unknown host reference '${name}' is not a declared canonical host ID"
      ) unknownReferences)
      (lib.throwIf (systemDrift != [ ]) (lib.concatStringsSep "; " systemDrift) deployTopology);

  deployConfig = import ../../lib/deploy {
    inherit (inputs) nixpkgs deploy-rs;
    nixosConfigurations = top.config.flake.nixosConfigurations;
    inherit (checkedDeployTopology) nodes;
  };
in
{
  flake = {
    inherit (deployConfig) deploy;
    deployHosts = checkedDeployTopology;
  };

  perSystem =
    { system, ... }:
    {
      checks = inputs.deploy-rs.lib.${system}.deployChecks top.config.flake.deploy;
    };
}
