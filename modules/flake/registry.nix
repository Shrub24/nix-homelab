# Flake-level bootstrap projection (Stage 8 dendritic-stage-8-host-identity-contracts
# task 2.3). Canonical host records — and the generic materializer that turns
# them into flake.nixosConfigurations — live in modules/flake/host-registry.nix;
# each host declares its own record from its discovered contributor at
# modules/hosts/<host>/default.nix. The transitional loader, the concrete
# nixos.configurations table, and the hostRecord submodule are gone.
#
# What remains is the reimage projection: bootstrap-carrying hosts get their
# hostName and flake reference derived from their record key (DS-5/DS-6).
{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    filterAttrs
    mapAttrs
    ;
in
{
  # hostName and flake are derived from the record key, not stored (DS-6).
  flake.bootstrap.nodes = mapAttrs (
    name: host:
    host.bootstrap
    // {
      hostName = name;
      flake = ".#${name}";
    }
  ) (filterAttrs (_: host: host.bootstrap != null) config.nixos.hosts);
}
