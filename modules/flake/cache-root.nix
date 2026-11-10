# `packages.cache-root` comes from nix-fleet's cacheRoot module, imported by
# nixbotEffects. `checks.packages` puts that root in the approved build
# selection, so a promoted revision has it in the cache: `pins create` refuses
# a path the cache does not hold.
{ ... }:
{
  perSystem =
    { config, ... }:
    {
      checks.packages = config.packages.cache-root;
    };
}
