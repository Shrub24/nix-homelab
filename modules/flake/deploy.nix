# deploy-rs wiring. lib/deploy/hosts.nix owns the physical topology (edgeHost,
# deployOrder, ssh users, remote-build flags); every host reference it makes must
# name a declared canonical host ID and every node's `system` must agree with
# that record — both fail closed with named errors, so a drifted topology cannot
# silently produce a deploy output. The topology keeps owning its own physical
# facts; they are never merged into the host records.
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
