# The registry half of the container runtime invariant: podman pulls the images the fleet's
# image policy references, and needs credentials at the host that runs them.
_: {
  flake.modules.nixos.containers =
    { config, lib, ... }:
    let
      containers = config.virtualisation.oci-containers.containers;
      cfg = config.services.containers;
    in
    {
      options.services.containers.registryAuth = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Authenticate Docker Hub pulls with `dockerhub/auth` from the fleet secret file,
          which must hold the base64 `user:token` blob Podman's auth.json accepts. Left
          false the anonymous pull budget applies.
        '';
      };

      config = lib.mkIf cfg.registryAuth {
        sops.secrets."dockerhub/auth" = { };

        sops.templates."containers-auth.json" = {
          content = builtins.toJSON {
            auths."docker.io".auth = config.sops.placeholder."dockerhub/auth";
          };
        };

        systemd.services = lib.mapAttrs' (
          name: _:
          lib.nameValuePair "podman-${name}" {
            environment.REGISTRY_AUTH_FILE = config.sops.templates."containers-auth.json".path;
          }
        ) containers;
      };
    };
}
