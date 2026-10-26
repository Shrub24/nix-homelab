# The registry half of the container runtime invariant: podman pulls the images the fleet's
# image policy references, and needs credentials at the host that runs them.
_: {
  flake.modules.nixos.containers =
    { config, lib, ... }:
    let
      containers = config.virtualisation.oci-containers.containers;

      # An operator who has not supplied the credential keeps the anonymous pull budget
      # rather than a failing unit.
      hasDockerHubAuth =
        containers != { }
        &&
          (import ../../lib/sops-keys.nix { inherit lib; }).hasKey config.sops.defaultSopsFile "dockerhub"
            "auth";
    in
    {
      sops.secrets = lib.optionalAttrs hasDockerHubAuth {
        # Podman's auth.json accepts only a base64 "user:token" blob, so the secret holds
        # that value rather than the pair.
        "dockerhub/auth" = { };
      };

      sops.templates = lib.optionalAttrs hasDockerHubAuth {
        "containers-auth.json".content = builtins.toJSON {
          auths."docker.io".auth = config.sops.placeholder."dockerhub/auth";
        };
      };

      systemd.services = lib.optionalAttrs hasDockerHubAuth (
        lib.mapAttrs' (
          name: _:
          lib.nameValuePair "podman-${name}" {
            environment.REGISTRY_AUTH_FILE = config.sops.templates."containers-auth.json".path;
          }
        ) containers
      );
    };
}
