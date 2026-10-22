# deploy-rs wiring over the physical topology in lib/deploy/hosts.nix. Host references and
# each node's `system` are validated against the canonical records, both failing closed.
top@{ inputs, lib, ... }:
let
  deployTopology = import ../../lib/deploy/hosts.nix;

  references =
    builtins.attrNames deployTopology.nodes
    ++ [ deployTopology.edgeHost ]
    ++ deployTopology.deployOrder;

  unknownReferences = lib.filter (name: !(top.config.nixos.hosts ? ${name})) (lib.unique references);

  # Not derived from the host record, but a disagreement activates the wrong architecture.
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

  # One named error per drift site, so an evaluation reports every drifted reference.
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
    let
      # Each activation profile is a check on the system that builds it, so `.#checks`
      # covers the deploy surface. `packages.host-*` mirrors them unfiltered for prebuilds.
      profileChecks =
        lib.mapAttrs' (name: node: lib.nameValuePair "host-${name}" node.profiles.system.path)
          (
            lib.filterAttrs (
              name: _: top.config.flake.deployHosts.nodes.${name}.system == system
            ) top.config.flake.deploy.nodes
          );
    in
    {
      checks = inputs.deploy-rs.lib.${system}.deployChecks top.config.flake.deploy // profileChecks;
    };
}
