# Typed host registry (DS-2). nixos.configurations.<host> records own the
# target system and the explicit composition; flake.nixosConfigurations is
# materialized from them through inputs.nixpkgs.lib.nixosSystem with each
# record's explicit system, so mixed-architecture evaluation never relies on
# the evaluator's current system. There is no specialArgs bus: aspects close
# over their dependencies lexically and host records import aspects
# explicitly.
{
  inputs,
  config,
  lib,
  ...
}:
let
  inherit (lib)
    filterAttrs
    mapAttrs
    mkOption
    types
    ;

  aspects = config.flake.modules.nixos;

  hostRecord = types.submodule (
    { config, ... }:
    {
      options = {
        system = mkOption {
          type = types.str;
          description = "Target system, materialized explicitly for mixed-arch evaluation.";
        };

        module = mkOption {
          type = types.deferredModule;
          description = "Host composition: explicit aspect, input-module, and leaf imports.";
        };

        bootstrap = mkOption {
          type = types.nullOr (types.attrsOf types.str);
          default = null;
          description = "Reimage-only metadata projected to flake.bootstrap.nodes.<host>.";
        };

        configuration = mkOption {
          type = types.raw;
          readOnly = true;
          description = "Evaluated NixOS configuration materialized from this record.";
          default = inputs.nixpkgs.lib.nixosSystem {
            system = config.system;
            modules = [ config.module ];
          };
        };
      };
    }
  );
in
{
  options.nixos.configurations = mkOption {
    type = types.lazyAttrsOf hostRecord;
    default = { };
    description = "Typed per-host composition records materialized into nixosConfigurations.";
  };

  config = {
    nixos.configurations = {
      oci-melb-1 = {
        system = "aarch64-linux";
        module = {
          imports = [
            inputs.disko.nixosModules.disko
            inputs.sops-nix.nixosModules.sops
            inputs.niks3.nixosModules.niks3
            inputs.niks3.nixosModules.niks3-auto-upload
            aspects.provenance
            aspects.cli
            aspects.oci-images
            aspects.fleet-packages
            ../hosts/oci-melb-1/default.nix
          ];
        };
        # Reimage-only facts (DS-5/DS-6): hostName and flake are derived from
        # the registry key in the bootstrap projection, never stored here.
        bootstrap = {
          bootstrapUser = "ubuntu";
          bootstrapDisk = "/dev/sda";
          mediaDisk = "/dev/sdb";
          rootPartitionSize = "20G";
          dataRoot = "/srv/data";
        };
      };

      la-admin-1 = {
        system = "x86_64-linux";
        module = {
          imports = [
            inputs.sops-nix.nixosModules.sops
            inputs.niks3.nixosModules.niks3-auto-upload
            aspects.provenance
            aspects.cli
            aspects.oci-images
            aspects.fleet-packages
            ../hosts/la-admin-1/default.nix
          ];
        };
      };

      home-forge = {
        # x86_64 physical host; the facter report exists and is wired through
        # hardware.facter.reportPath in the host composition below. The target
        # system is still pinned explicitly for mixed-arch materialization (DS-2).
        system = "x86_64-linux";
        module = {
          imports = [
            inputs.disko.nixosModules.disko
            inputs.sops-nix.nixosModules.sops
            inputs.niks3.nixosModules.niks3-auto-upload
            aspects.provenance
            aspects.cli
            aspects.oci-images
            aspects.fleet-packages
            aspects.dj
            ../hosts/home-forge/default.nix
          ];
        };
      };
    };

    flake.nixosConfigurations = mapAttrs (_: host: host.configuration) config.nixos.configurations;

    # hostName and flake are derived from the registry key, not stored (DS-6).
    flake.bootstrap.nodes = mapAttrs (
      name: host:
      host.bootstrap
      // {
        hostName = name;
        flake = "path:.#${name}";
      }
    ) (filterAttrs (_: host: host.bootstrap != null) config.nixos.configurations);
  };
}
