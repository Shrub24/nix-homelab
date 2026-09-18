# Canonical fleet host registry (dendritic-stage-8-host-identity-contracts
# HIC-1/HIC-2, task 2.1): one typed record per stable host ID, validated with
# named errors and materialized generically into nixosConfigurations. This file
# names no concrete host; task 2.2 makes each host contributor declare its own
# record through discovery. Records stay deferred data so validation and
# materialization run only after option merging — placement is never derived
# from an evaluated NixOS config (design risk: recursive module evaluation
# cycle).
#
# Stage 8 task 2.3: every record below is declared by its discovered contributor
# at modules/hosts/<host>/default.nix. `hosts` left the import-tree exclusion and
# the transitional loader is gone, so each contributor loads exactly once and
# modules/flake/registry.nix keeps only the bootstrap projection.
{
  inputs,
  config,
  lib,
  ...
}:
let
  inherit (lib)
    concatStringsSep
    filter
    length
    map
    mapAttrs
    mkOption
    optionals
    types
    ;

  hostIdPattern = "[a-z0-9][a-z0-9-]*";

  # builtins.match anchors both ends, so this is a full-string shape check.
  validHostId = id: builtins.match hostIdPattern id != null;

  hostRecord = types.submodule (
    { name, config, ... }:
    {
      options = {
        hostId = mkOption {
          type = types.str;
          default = name;
          defaultText = lib.literalExpression "the host registry attribute key";
          description = "Stable canonical host ID; defaults to the registry key.";
        };

        system = mkOption {
          type = types.nullOr (
            types.enum [
              "aarch64-linux"
              "x86_64-linux"
            ]
          );
          default = null;
          description = "Target system, materialized explicitly so mixed-architecture evaluation never relies on the evaluator's current system.";
        };

        tailscale = mkOption {
          default = { };
          description = "Tailscale identity owning the private FQDN.";
          type = types.submodule {
            options = {
              hostname = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Tailscale machine hostname.";
              };

              tailnetSuffix = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Tailnet DNS suffix (for example tail0fe19b.ts.net); task 3.2 supplies the fleet value.";
              };

              fqdn = mkOption {
                type = types.nullOr types.str;
                readOnly = true;
                default =
                  if config.tailscale.hostname == null || config.tailscale.tailnetSuffix == null then
                    null
                  else
                    "${config.tailscale.hostname}.${config.tailscale.tailnetSuffix}";
                description = "Derived private FQDN; null until both hostname and tailnetSuffix are known.";
              };
            };
          };
        };

        composition = mkOption {
          default = { };
          description = "Deferred NixOS composition owned by this host record.";
          type = types.submodule {
            options = {
              aspects = mkOption {
                type = types.listOf types.deferredModule;
                default = [ ];
                description = "Aspect selections from flake.modules.nixos.<name>; selection is enablement.";
              };

              extraModules = mkOption {
                type = types.listOf types.deferredModule;
                default = [ ];
                description = "Input module imports (disko, sops-nix, niks3 modules).";
              };

              fragments = mkOption {
                type = types.listOf (types.either types.path types.deferredModule);
                default = [ ];
                description = "Host-private NixOS fragments; task 2.2 moves these under explicit private paths.";
              };
            };
          };
        };

        bootstrap = mkOption {
          type = types.nullOr (types.attrsOf types.str);
          default = null;
          description = "Reimage-only metadata; the registry projects it to flake.bootstrap.nodes.<host>.";
        };

        # No deployment field here: HIC-3 keeps physical SSH/deploy facts in
        # their own authority (lib/deploy/hosts.nix) and has it reference
        # canonical host IDs instead of duplicating the facts in the record.

        configuration = mkOption {
          type = types.nullOr types.raw;
          readOnly = true;
          default =
            if config.system == null then
              null
            else
              inputs.nixpkgs.lib.nixosSystem {
                inherit (config) system;
                modules =
                  config.composition.extraModules
                  ++ config.composition.aspects
                  ++ config.composition.fragments
                  ++ optionals (config.tailscale.hostname != null) [
                    { networking.hostName = config.tailscale.hostname; }
                  ];
              };
          description = "Evaluated NixOS configuration materialized from this record.";
        };
      };
    }
  );

  hosts = config.nixos.hosts;
  hostKeys = builtins.attrNames hosts;
  declaredIds = map (key: hosts.${key}.hostId) hostKeys;
  countId = id: length (filter (x: x == id) declaredIds);
  tailscaleHostnames = filter (name: name != null) (
    map (key: hosts.${key}.tailscale.hostname) hostKeys
  );
  countTailscale = name: length (filter (x: x == name) tailscaleHostnames);

  # Every failure is a named 'host-registry:' error so checks can assert the
  # exact reason instead of a generic option error.
  validationErrors =
    map (id: "host-registry: duplicate host ID '${id}' is declared by more than one host record") (
      filter (id: countId id > 1) declaredIds
    )
    ++ map (id: "host-registry: invalid host ID '${id}' must match ^${hostIdPattern}$") (
      filter (id: !(validHostId id)) declaredIds
    )
    ++ map (
      key: "host-registry: host ID '${hosts.${key}.hostId}' does not match its registry key '${key}'"
    ) (filter (key: hosts.${key}.hostId != key) hostKeys)
    ++ map (
      name: "host-registry: duplicate Tailscale identity '${name}' is used by more than one host record"
    ) (filter (name: countTailscale name > 1) tailscaleHostnames)
    ++ map (key: "host-registry: host '${key}' is missing required system or tailscale.hostname") (
      filter (key: hosts.${key}.system == null || hosts.${key}.tailscale.hostname == null) hostKeys
    );
in
{
  options.nixos.hosts = mkOption {
    type = types.lazyAttrsOf hostRecord;
    default = { };
    description = "Typed canonical host records keyed by stable host ID, materialized into nixosConfigurations.";
  };

  options.nixos.hostValidationErrors = mkOption {
    type = types.listOf types.str;
    default = [ ];
    description = "Named canonical-host-identity validation errors; empty means the declared registry is valid.";
  };

  config = {
    nixos.hostValidationErrors = validationErrors;

    flake.nixosConfigurations = lib.throwIf (validationErrors != [ ]) (
      "host-registry: refusing to materialize hosts: " + concatStringsSep "; " validationErrors
    ) (mapAttrs (_: host: host.configuration) hosts);
  };
}
