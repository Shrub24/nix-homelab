# Bootstrap projection over the canonical host records
# (modules/flake/host-registry.nix): bootstrap-carrying hosts get their hostName
# and flake reference derived from their record key.
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
  flake.bootstrap.nodes = mapAttrs (
    name: host:
    host.bootstrap
    // {
      hostName = name;
      flake = ".#${name}";
    }
  ) (filterAttrs (_: host: host.bootstrap != null) config.nixos.hosts);
}
