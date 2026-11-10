{
  nixpkgs,
  deploy-rs,
  nodes,
  nixosConfigurations,
}:
let
  inherit (nixpkgs) lib;

  # Only `nodes` may feed node construction; `edgeHost` and `deployOrder` are never NixOS
  # nodes. `deployable = false` marks hosts in the topology that deploy-rs must skip.
  deployableNodes = lib.filterAttrs (_: host: host.deployable or true) nodes;
  deployNode =
    name: host:
    let
      sshOpts = host.sshOpts or [ ];
    in
    {
      hostname = host.hostName;
      inherit (host) sshUser;
      inherit sshOpts;
      profiles.system = {
        user = "root";
        remoteBuild = host.remoteBuild or false;
        # The 240s default is shorter than a switch on these hosts on its own.
        activationTimeout = 900;
        path = deploy-rs.lib.${host.system}.activate.nixos nixosConfigurations.${name};
      };
    };
  deploy = {
    nodes = lib.mapAttrs deployNode deployableNodes;
  };
in
{
  inherit deploy;
}
