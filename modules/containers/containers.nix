# The container runtime baseline: upstream's podman aspect (full-image prune, restart bound,
# failure event), plus the unit revision derived below. Registry credentials join in
# container-auth.nix.
# The env path is stable and its content never enters the unit, so a changed environment
# leaves it byte-identical and the container keeps old variables, silently.
{ inputs, ... }:
{
  flake.modules.nixos.containers =
    { config, lib, ... }:
    let
      containers = config.virtualisation.oci-containers.containers;
      templates = config.sops.templates;
      secrets = config.sops.secrets;

      # Templates name their secrets only through `<SOPS:sha256(<name>):PLACEHOLDER>`, so
      # the mapping runs back through that hash.
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
      imports = [ inputs.nix-fleet.modules.nixos.podman ];

      systemd.services = lib.mapAttrs' (
        name: container:
        lib.nameValuePair "podman-${name}" {
          unitConfig."X-Container-Env-Revision" = revisionOf container;
        }
      ) (lib.filterAttrs (_: container: container.environmentFiles != [ ]) containers);
    };
}
