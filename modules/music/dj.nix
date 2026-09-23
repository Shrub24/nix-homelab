# DJ aspect: owns the traktor-m3u-sync input module/package, the
# applications.dj enablement contract, and the host-matched windows-dj-setup
# payload. The engine host and the Windows VM workload are sibling
# contributors of the same publication (./dj-engine.nix, ./windows-vm.nix).
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

      options.applications.dj.enable = lib.mkEnableOption "DJ application composition (Windows VM workloads)";

      # The module declares options above, so its configuration is nested.
      config = {
        services.traktor-m3u-sync.package =
          inputs.traktor-m3u-sync.packages.${pkgs.stdenv.hostPlatform.system}.default;

        applications.dj.enable = true;

        applications.dj.engine.setupPackage = withSystem pkgs.stdenv.hostPlatform.system (
          { config, ... }: config.packages.windows-dj-setup
        );
      };
    };
}
