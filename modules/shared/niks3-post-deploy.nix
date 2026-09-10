{
  config,
  lib,
  ...
}:
let
  cfg = config.services.niks3-post-deploy;
  hook = config.services.niks3-auto-upload;
  hookPkg = hook.package;
  # Required typed option injected by the backups aspect (OPS-3); the leaf no
  # longer reads config.repo.packages, so the aspect has no hidden
  # fleet-packages dependency.
  filterPkg = cfg.filterPackage;
in
{
  options.services.niks3-post-deploy = {
    enable = lib.mkEnableOption "post-deploy push of filtered system closure to niks3";

    filterPackage = lib.mkOption {
      type = lib.types.package;
      description = "nix-path-filter package used to exclude public-key-signed paths from the pushed closure.";
    };

    excludePublicKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "cache.nixos.org"
        "nix-community.cachix.org"
        "cache.numtide.com"
      ];
      description = "Signing key prefixes to exclude from push. Paths signed only by these keys are skipped.";
    };
  };

  config = lib.mkIf cfg.enable {
    # OPS-6: classified upstream compatibility constraint. Upstream
    # niks3-auto-upload sets nix.settings.post-build-hook whenever it is
    # enabled; the fleet deliberately does not run the hook on every Nix
    # build (post-deploy closure upload is activation-triggered against the
    # same daemon/socket), so this mkForce "" suppresses the automatic hook.
    # Do not remove or relocate; no other override exists.
    nix.settings.post-build-hook = lib.mkForce "";

    # Runs on every activation (switch and boot). At boot systemd is not up
    # yet (stage-2 activates before exec systemd), so the guard skips the
    # start there; at switch time the service is triggered directly. The
    # target file carries the *new* toplevel so the service never races the
    # final ln -sfn /run/current-system, which happens after all snippets.
    system.activationScripts.niks3-post-deploy = ''
      mkdir -p /run/niks3-post-deploy
      readlink -f "$systemConfig" > /run/niks3-post-deploy/target
      if [ -e /run/systemd/system ]; then
        ${config.systemd.package}/bin/systemctl start --no-block niks3-post-deploy.service || true
      fi
    '';

    systemd.services.niks3-post-deploy = {
      description = "Queue system closure delta for niks3 upload";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [
        hookPkg
        filterPkg
      ];
      serviceConfig = {
        Type = "oneshot";
        ProtectSystem = "strict";
        PrivateTmp = true;
      };

      environment = {
        EXCLUDE_PUBLIC_KEYS = lib.concatStringsSep " " cfg.excludePublicKeys;
      };

      script = ''
        set -euo pipefail
        SYSTEM=$(cat /run/niks3-post-deploy/target 2>/dev/null || readlink -f /run/current-system)
        OUR_PATHS=$(${filterPkg}/bin/nix-path-filter --exclude "$EXCLUDE_PUBLIC_KEYS" "$SYSTEM" 2>/dev/null || true)
        if [ -z "$OUR_PATHS" ]; then
          echo "No paths to push after filtering, skipping"
          exit 0
        fi
        export OUT_PATHS="$(echo "$OUR_PATHS" | tr '\n' ' ')"
        exec ${lib.getExe' hookPkg "niks3-hook"} send
      '';
    };
  };
}
