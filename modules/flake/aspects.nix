# Cross-cutting NixOS aspects (DS-3, DS-4). Each flake.modules.nixos.<name> is
# an ordinary deferred module; host registry records opt in explicitly. Aspects
# own the flake dependencies that previously leaked into every module through
# specialArgs (self, inputs, ociImages).
{
  inputs,
  lib,
  self,
  withSystem,
  ...
}:
let
  ociImagesPolicy = import ../../policy/oci-images.nix;
in
{
  # Repository provenance; replaces the args.self handling in core/base.nix.
  flake.modules.nixos.provenance = {
    system.configurationRevision = self.rev or self.dirtyRev or null;
    environment.etc."nixos-source".source = self.outPath;
  };

  # Common CLI input module (nix-index), closed over here instead of per host.
  flake.modules.nixos.cli = {
    imports = [ inputs.nix-index-database.nixosModules.nix-index ];
  };

  # Typed OCI image policy at the NixOS module boundary (DS-4): services read
  # config.repo.ociImages.<name> instead of an ociImages flake argument.
  flake.modules.nixos.oci-images =
    { ... }:
    {
      options.repo.ociImages = lib.mkOption {
        type = lib.types.attrs;
        readOnly = true;
        description = "Canonical OCI image refs from policy/oci-images.nix.";
      };

      config.repo.ociImages = ociImagesPolicy;
    };

  # Repository packages consumable by service modules, resolved for the
  # evaluated host's target system (replaces self.packages.${...} in leaf
  # modules). Explicit allowlist: host-* convenience packages embed deploy-node
  # profile paths that depend on nixosConfigurations, so projecting the full
  # perSystem attrset would open a recursion back into the module space.
  flake.modules.nixos.fleet-packages =
    { pkgs, ... }:
    {
      options.repo.packages = lib.mkOption {
        type = lib.types.attrs;
        readOnly = true;
        description = "Service-consumable repository packages for this host's target system.";
      };

      config.repo.packages = withSystem pkgs.stdenv.hostPlatform.system (
        { config, ... }:
        {
          inherit (config.packages)
            nix-path-filter
            notification-daemon
            notify
            ;
        }
      );
    };
}
