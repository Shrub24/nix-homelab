# Physical deployment topology, separate from deploy-rs node definitions. Only `nodes`
# feeds node generation; `edgeHost` and `deployOrder` are scheduling facts, never nodes.
{
  # Active public edge host: the only host that projects the route catalog and
  # terminates public TLS.
  edgeHost = "oci-melb-1";

  # Serial deployment order for regular deploys.
  deployOrder = [
    "la-admin-1"
    "oci-melb-1"
  ];

  # Deploy-rs node definitions. Each key must also exist as a
  # nixosConfiguration in flake.nix.
  nodes = {
    oci-melb-1 = {
      hostName = "oci-melb-1";
      sshUser = "dev";
      system = "aarch64-linux";
      remoteBuild = true;
      strictSubstituteOnly = false;
    };

    la-admin-1 = {
      hostName = "la-admin-1";
      sshUser = "dev";
      system = "x86_64-linux";
      remoteBuild = false;
      strictSubstituteOnly = false;
    };

    home-forge = {
      hostName = "home-forge";
      sshUser = "dev";
      system = "x86_64-linux";
      remoteBuild = true;
      strictSubstituteOnly = false;
    };
  };
}
