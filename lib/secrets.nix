{
  lib,
}:
{
  mkSecretFileOption =
    name:
    lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to SOPS-encrypted file for ${name} secrets.";
    };

  # Service- and application-scoped files are host-agnostic: the owning module defaults its
  # option, and a host overrides only when it must.
  mkSecretFileOptionWithDefault =
    name: default:
    lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      inherit default;
      description = "Path to SOPS-encrypted file for ${name} secrets.";
    };

  mkSecretKeyOption =
    defaultKey:
    lib.mkOption {
      type = lib.types.str;
      default = defaultKey;
      description = "SOPS YAML key path for this secret.";
    };

  mkSecretsFromMap =
    sopsFile: map:
    builtins.mapAttrs (_name: spec: {
      inherit sopsFile;
      inherit (spec) key path;
      owner = spec.owner or "root";
      group = spec.group or "root";
      mode = spec.mode or "0400";
      restartUnits = spec.restartUnits or [ ];
    }) map;
}
