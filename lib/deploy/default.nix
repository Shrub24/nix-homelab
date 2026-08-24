{
  self,
  nixpkgs,
  deploy-rs,
  nodes,
}:
let
  lib = nixpkgs.lib;

  # Only the `nodes` map from lib/deploy/hosts.nix may feed node construction;
  # physical topology facts (`edgeHost`, `deployOrder`) must never be treated
  # as NixOS nodes. Nodes explicitly marked `deployable = false` are physical
  # hosts that exist in topology metadata but are excluded from deploy-rs
  # (e.g. locally-managed hosts deployed via `nixos-rebuild --target-host`).
  deployableNodes = lib.filterAttrs (_: host: host.deployable or true) nodes;
  deployNode =
    name: host:
    let
      sshOpts = host.sshOpts or [ ];
      # postDeploy must use the same ssh config as the deploy itself.
      sshCommand = lib.concatStringsSep " " (
        [ "ssh" ] ++ sshOpts ++ [ "${host.sshUser}@${host.hostName}" ]
      );
    in
    {
      hostname = host.hostName;
      sshUser = host.sshUser;
      sshOpts = sshOpts;
      profiles.system = {
        user = "root";
        remoteBuild = host.remoteBuild or false;
        path = deploy-rs.lib.${host.system}.activate.nixos self.nixosConfigurations.${name};
        postDeploy = ''
          ${sshCommand} "apprise-notify warning 'Deploy to ${name} completed successfully'" 2>/dev/null || true
        '';
      };
    };

  systems = lib.unique (lib.attrValues (lib.mapAttrs (_: host: host.system) deployableNodes));
  deploy = {
    nodes = lib.mapAttrs deployNode deployableNodes;
  };
in
{
  inherit deploy;

  checks = lib.genAttrs systems (system: deploy-rs.lib.${system}.deployChecks deploy);
}
