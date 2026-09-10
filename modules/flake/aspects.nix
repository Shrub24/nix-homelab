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
        # OPS-4: notify owns monitor composition (canonical apprise contract).
        # The state-backups leaf no longer defaults monitor.enable on; the
        # backups aspect asserts this option instead of importing notify.
        monitor.enable = true;
      };
    };

  # --- Operational aspects (dendritic stage 3, OPS-1) ----------------------
  # Backups: host-egress capability composing state backups, the niks3 upload
  # client, and post-deploy closure upload. Selection is enablement; the aspect
  # imports the upstream niks3-auto-upload module itself and injects the
  # required nix-path-filter package per system via withSystem, so it has no
  # hidden fleet-packages dependency. The conventional host secret path gates
  # the whole capability (two-step sops bootstrap, OPS-3).
  flake.modules.nixos.backups =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hostSystemSecret = ../../secrets/hosts + "/${config.networking.hostName}/system.yaml";
      hasHostSecrets = builtins.pathExists hostSystemSecret;
      bucketName = "shrublab-backup-${config.networking.hostName}";
      # S3 bucket rule (OPS-11): 3-63 chars, lowercase alnum/hyphens, alnum at both ends.
      bucketNameValid = builtins.match "^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$" bucketName != null;
      packages = withSystem pkgs.stdenv.hostPlatform.system (
        { config, ... }:
        {
          inherit (config.packages) nix-path-filter;
        }
      );
    in
    {
      imports = [
        inputs.niks3.nixosModules.niks3-auto-upload
        ../services/state-backups.nix
        ../shared/niks3-upload-client.nix
        ../shared/niks3-post-deploy.nix
      ];

      # The whole host-egress capability activates only when the conventional
      # host secret exists; the client leaf gates itself on the same path
      # (OPS-5). The derived bucket and secret path replace the three host
      # literals, which all equal the convention exactly.
      services.state-backups = lib.mkIf hasHostSecrets {
        enable = true;
        secretFile = hostSystemSecret;
        bucket = lib.mkDefault bucketName;
      };

      services.niks3-post-deploy = lib.mkIf hasHostSecrets {
        enable = true;
        filterPackage = packages.nix-path-filter;
      };

      assertions = [
        {
          assertion = bucketNameValid;
          message = "backups aspect: derived bucket '${bucketName}' must be a valid S3 bucket name (3-63 lowercase alnum/hyphen).";
        }
      ]
      ++ lib.optionals hasHostSecrets [
        {
          # OPS-4: backups never imports notify; it asserts the actual monitor
          # option so a host selecting backups without notify fails with a named
          # message instead of silently missing its failure-monitoring template.
          assertion = lib.attrByPath [ "services" "notification-daemon" "monitor" "enable" ] false config;
          message = "backups aspect: services.notification-daemon.monitor.enable must be true (select the notify aspect) so restic-backups-state failures route through svc-monitor.";
        }
      ];
    };

  # Builder access: nixbuild.net SSH trust only (OPS-7). Substituter policy
  # stays in the base aspect; the retired fleet.nixbuild-ssh.enable option is
  # replaced by this aspect's selection.
  flake.modules.nixos.builder-access = {
    imports = [ ../shared/nixbuild-ssh.nix ];
  };

  # Observability agent: Beszel agent authentication and enrollment (OPS-8).
  # The aspect derives the conventional host secret path and gates enrollment
  # on its existence; the Beszel hub remains an admin-service leaf.
  flake.modules.nixos.observability-agent =
    { config, lib, ... }:
    let
      hostSystemSecret = ../../secrets/hosts + "/${config.networking.hostName}/system.yaml";
      hasHostSecrets = builtins.pathExists hostSystemSecret;
    in
    {
      imports = [ ../services/beszel-agent-auth.nix ];

      services.beszel-agent-auth = lib.mkIf hasHostSecrets {
        enable = true;
        secretFiles.host = hostSystemSecret;
      };
    };
}
