# DJ aspect (DS-4): owns the traktor-m3u-sync input module/package and the
# host-matched windows-dj-setup payload that engine-dj reached via inputs/self.
{ inputs, withSystem, ... }:
{
  flake.modules.nixos.dj =
    { pkgs, ... }:
    {
      imports = [
        inputs.traktor-m3u-sync.nixosModules.default
        ../applications/dj
      ];

      services.traktor-m3u-sync.package =
        inputs.traktor-m3u-sync.packages.${pkgs.stdenv.hostPlatform.system}.default;

      # Selecting the DJ deployment aspect is its top-level enablement (S4-4).
      applications.dj.enable = true;

      applications.dj.engine.setupPackage = withSystem pkgs.stdenv.hostPlatform.system (
        { config, ... }: config.packages.windows-dj-setup
      );
    };
}
