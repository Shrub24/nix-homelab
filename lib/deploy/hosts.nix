# Physical deployment topology facts, separated from deploy-rs node definitions.
#
# Only `nodes` feeds deploy-rs node generation (see lib/deploy/default.nix).
# `edgeHost` and `deployOrder` are physical-host facts for scripts, tests, and
# deployment sequencing; they must never be interpreted as NixOS nodes.
{
  # Active public edge/admin host.
  edgeHost = "la-admin-1";

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
      bootstrapHostName = "216.75.75.168";
      sshUser = "dev";
      system = "x86_64-linux";
      remoteBuild = false;
      strictSubstituteOnly = false;
      hostKeyFingerprint = "SHA256:g71ri368dh+EkeJgXrHmMsrxlkwHI2T9G8rFD+G6fWw";
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
