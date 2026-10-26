# Deploy-rs wiring over the physical topology in lib/deploy/hosts.nix, and the published
# `fleet` view of the same validated records. Host references and each node's `system` are
# validated against the canonical records, both failing closed.
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

  # Everything about a host under one key: the validated deploy facts plus the
  # reimage metadata its canonical record declares. Adopted hosts carry no
  # `bootstrap` attribute at all rather than an empty one.
  fleetHosts = lib.mapAttrs (
    name: node:
    node
    // lib.optionalAttrs ((top.config.nixos.hosts.${name}.bootstrap or null) != null) {
      bootstrap = top.config.nixos.hosts.${name}.bootstrap // {
        hostName = name;
        flake = ".#${name}";
      };
    }
  ) checkedDeployTopology.nodes;
in
{
  flake = {
    # deploy-rs owns this schema; `deployChecks` and `nix run .#deploy-rs` read it.
    inherit (deployConfig) deploy;

    fleet = {
      inherit (checkedDeployTopology) edgeHost deployOrder;
      hosts = fleetHosts;
    };
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
              name: _: checkedDeployTopology.nodes.${name}.system == system
            ) top.config.flake.deploy.nodes
          );
    in
    {
      checks = inputs.deploy-rs.lib.${system}.deployChecks top.config.flake.deploy // profileChecks;
    };
}
