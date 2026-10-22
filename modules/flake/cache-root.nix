# The retention root: the artefact aggregate the cache's pin holds a name
# against and its verification measures. `packages.cache-root` is a linkFarm over
# every published package, so its closure is exactly the artefact set (verdicts
# answer questions about a revision and would move on every commit).
#
# `checks.packages` puts that root in the approved build selection — a promoted
# revision therefore has it in the cache, which `pins create` requires: it
# refuses a path the cache does not hold.
{ lib, ... }:
{
  perSystem =
    { config, pkgs, ... }:
    {
      packages.cache-root = pkgs.linkFarm "cache-root" (
        lib.mapAttrsToList (name: path: { inherit name path; }) (
          lib.filterAttrs (name: _: name != "cache-root") config.packages
        )
      );

      checks.packages = config.packages.cache-root;
    };
}
