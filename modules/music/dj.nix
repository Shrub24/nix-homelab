# DJ: the traktor-m3u-sync package, its Windows VM workloads, and the read-only music contract.
# payload. Engine host and VM are sibling contributors of the same publication.
{
  inputs,
  lib,
  withSystem,
  ...
}:
{
  flake.modules.nixos.dj =
    { pkgs, ... }:
    {
      imports = [ inputs.traktor-m3u-sync.nixosModules.default ];

      config = {
        services.traktor-m3u-sync.package =
          inputs.traktor-m3u-sync.packages.${pkgs.stdenv.hostPlatform.system}.default;

        applications.dj.engine.setupPackage = withSystem pkgs.stdenv.hostPlatform.system (
          { config, ... }: config.packages.windows-dj-setup
        );
      };
    };
}
