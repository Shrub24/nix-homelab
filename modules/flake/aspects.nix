# Cross-cutting NixOS aspects (DS-3, DS-4). Each flake.modules.nixos.<name> is
# an ordinary deferred module; host registry records opt in explicitly. Aspects
# own the flake dependencies that previously leaked into every module through
# specialArgs (self, inputs, ociImages).
#
# Foundation aspects (FND-1): base, shell, networking, tailscale, notify.
# Selecting an aspect is its enablement; no aspect imports another aspect.
# Each aspect may import its own private NixOS leaf (modules/flake/_aspects/
# or a service/shared leaf) without creating a hidden public dependency. All
# registry hosts select all five foundation aspects.
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

  # --- Foundation aspects (dendritic stage 2, FND-1) ------------------------
  flake.modules.nixos.base = {
    imports = [ ./_aspects/base.nix ];
  };

  flake.modules.nixos.shell = {
    imports = [
      inputs.nix-index-database.nixosModules.nix-index
      ./_aspects/shell.nix
    ];
  };

  flake.modules.nixos.networking = {
    imports = [ ./_aspects/networking.nix ];
  };

  flake.modules.nixos.tailscale = {
    imports = [ ../services/tailscale.nix ];
  };

  flake.modules.nixos.notify =
    { pkgs, ... }:
    let
      packages = withSystem pkgs.stdenv.hostPlatform.system (
        { config, ... }:
        {
          inherit (config.packages) notification-daemon notify;
        }
      );
    in
    {
      imports = [ ../services/notification-daemon ];
      services.notification-daemon = {
        enable = true;
        package = packages.notification-daemon;
        notifyPackage = packages.notify;
      };
    };
}
