# Rendered ahead of the proxy handler: Caddy's handle blocks are exclusive.
{ lib, ... }:
{
  options.services.ingress.staticPages = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf lib.types.path);
    default = { };
    description = "Files served by the edge, keyed by route name and then by public path.";
  };
}
