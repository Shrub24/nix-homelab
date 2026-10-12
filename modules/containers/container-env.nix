# Container environment revisions: one all-host invariant.
#
# `virtualisation.oci-containers` hands `podman run` a *stable* env-file path -- a sops
# template renders to /run/secrets/rendered/<name>, a secret used directly sits at
# /run/secrets/<name> -- and that file's content never appears in the unit definition.
# A changed environment therefore leaves the unit byte-identical: systemd does not
# restart it, and the running container keeps the variables it was created with. The
# failure is silent -- a deploy reports success while the container serves the old
# environment. (oci-melb-1, 2026-10-01: a deploy that added an OIDC variable left
# Langfuse running the container it had created eight hours earlier, so the fix stayed
# inert until something unrelated changed the unit. Only a unit change recreates the
# container: the generated start script is `podman run --replace` behind a
# `podman rm -f` pre-start, so a restart is enough once it happens.
# `restartTriggers = [ environmentFile ]` cannot help -- the path is constant, only
# what it points at changes.)
#
# This contributor derives a revision per container from everything its environment
# depends on, so the unit differs exactly when the environment would:
#
#   * the env-file paths themselves, so a container re-pointed at another file moves;
#   * every sops template's content -- the variable set, the part evaluation can see;
#   * the ciphertext of each sops file whose secrets a template interpolates, and of an
#     env file that is itself a secret. Values are decrypted at activation and never
#     reachable from evaluation, but any edit re-encrypts the file, so a rotated value
#     recreates the container too.
#
# Selected by every host that runs containers; a host without them gets an empty
# service set.
{ ... }:
{
  flake.modules.nixos.container-env =
    { config, lib, ... }:
    let
      containers = config.virtualisation.oci-containers.containers;
      templates = config.sops.templates;
      secrets = config.sops.secrets;

      # sops-nix renders `${config.sops.placeholder.<name>}` into a template as
      # `<SOPS:sha256(<secret name>):PLACEHOLDER>`, which is how the activation-time
      # renderer finds the value to substitute. That marker is the only thing in a
      # template naming its secrets, so the mapping runs back through the hash.
      secretNameByHash = lib.foldl' (
        acc: name:
        acc
        // {
          ${builtins.hashString "sha256" name} = name;
        }
      ) { } (lib.attrNames secrets);

      markerHashesIn =
        content:
        builtins.filter (hash: hash != null) (
          map (piece: builtins.match "([0-9a-f]{64}):PLACEHOLDER>" piece) (
            lib.tail (lib.splitString "<SOPS:" content)
          )
        );

      firstOrNull = names: if names == [ ] then null else lib.head names;

      # Rendered path -> the template or secret that writes it.
      templateNameAt =
        path: firstOrNull (lib.filter (name: templates.${name}.path == path) (lib.attrNames templates));
      secretNameAt =
        path: firstOrNull (lib.filter (name: secrets.${name}.path == path) (lib.attrNames secrets));

      readIfPresent =
        file: lib.optionalString (file != null && builtins.pathExists file) (builtins.readFile file);
      sopsFileOf = name: if name == null then "" else readIfPresent (secrets.${name}.sopsFile or null);

      revisionOf =
        container:
        let
          paths = container.environmentFiles;
          contents = map (
            path:
            let
              template = templateNameAt path;
            in
            lib.optionalString (template != null) templates.${template}.content
          ) paths;
        in
        builtins.hashString "sha256" (
          lib.concatStringsSep "\n" (
            map toString paths
            ++ contents
            ++ map (path: sopsFileOf (secretNameAt path)) paths
            ++ lib.concatMap (
              content: map (hash: sopsFileOf (secretNameByHash.${hash} or null)) (markerHashesIn content)
            ) contents
          )
        );
    in
    {
      systemd.services = lib.mapAttrs' (
        name: container:
        lib.nameValuePair "podman-${name}" {
          unitConfig."X-Container-Env-Revision" = revisionOf container;
        }
      ) (lib.filterAttrs (_: container: container.environmentFiles != [ ]) containers);
    };
}
