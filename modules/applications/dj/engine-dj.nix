# Engine DJ library hosting: a Windows VM instance serves Engine Remote
# Library to the SC6000 while the library database stays on Linux ext4.
# Single-writer discipline between the guest and future Linux sync workers is
# enforced by systemd Conflicts=; backups quiesce the VM via state-backups
# hooks. Guest software (Windows, Engine DJ, virtio-win) is installed by the
# operator — see docs/runbooks/engine-dj-guest-setup.md.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.applications.dj;
  engine = cfg.engine;

  engineEnabled = cfg.enable && engine.enable;
  vmUnit = "windows-vm-${engine.vmName}.service";
in
{
  imports = [
    ../../services/virtualisation/windows-vm.nix
  ];

  options.applications.dj = {
    engine = {
      enable = lib.mkEnableOption "Engine DJ library hosting on a Windows VM";

      vmName = lib.mkOption {
        type = lib.types.str;
        default = "windows-dj";
        description = "windows-vm instance name hosting Engine DJ.";
      };

      libraryPath = lib.mkOption {
        type = lib.types.str;
        default = "/srv/data/engine-dj/library";
        description = "Host directory holding the Engine library database (ext4 service state). Exclusive access alternates between the VM and Linux-side writers.";
      };

      mediaPath = lib.mkOption {
        type = lib.types.str;
        default = "/srv/storage/music";
        description = "Host music directory shared read-only into the guest.";
      };

      vcpu = lib.mkOption {
        type = lib.types.ints.positive;
        default = 4;
        description = "Guest vCPU count.";
      };

      memoryGiB = lib.mkOption {
        type = lib.types.ints.positive;
        default = 8;
        description = "Guest memory in GiB.";
      };

      spicePort = lib.mkOption {
        type = lib.types.port;
        default = 5900;
        description = "Loopback SPICE port for remote display (SSH tunnel over Tailscale).";
      };
    };
  };

  config = lib.mkIf engineEnabled {
    services.windows-vm = {
      enable = true;
      instances.${engine.vmName} = {
        inherit (engine) vcpu spicePort;
        memory = engine.memoryGiB * 1024;
        # Guest is Windows 11: emulated TPM 2.0 is an installer hard requirement.
        tpm = true;
        shares = {
          # Library share: read-write, stable mount tag. The guest maps it to
          # a fixed drive letter and symlinks Music\Engine Library to it once
          # (runbook); changing the tag breaks recorded track paths.
          library.source = engine.libraryPath;
          # Music share: authoritative media tree, never guest-writable.
          media = {
            source = engine.mediaPath;
            readonly = true;
          };
        };
      };
    };

    # Writer seam for future Linux-side library workers (libdjinterop m3u
    # sync etc.): workers bind to this target and inherit its mutual
    # exclusion with the VM unit. No worker exists yet — the target is the
    # contract.
    systemd.targets.dj-library-writers = {
      description = "Engine DJ library Linux-side writers (mutually exclusive with ${vmUnit})";
    };
    systemd.services."windows-vm-${engine.vmName}".conflicts = [ "dj-library-writers.target" ];

    systemd.tmpfiles.rules = [
      "d ${engine.libraryPath} 0755 root root - -"
      "d ${engine.mediaPath} 0755 root root - -"
    ];

    # Backup contract: quiesce mode — stop the VM only if it was running,
    # back up the library directory, restore prior running state afterwards.
    services.state-backups.services.engine-dj = {
      enable = true;
      mode = "quiesce";
      paths = [ engine.libraryPath ];
      prepareCommands = [
        ''
          # Fail closed: an undeterminable VM state aborts the backup (visible
          # via the restic unit's OnFailure notification) rather than risking
          # a snapshot of a live SQLite database.
          state=$(${pkgs.libvirt}/bin/virsh domstate ${engine.vmName} 2>/dev/null) || {
            echo "engine-dj: cannot determine ${engine.vmName} state, aborting backup" >&2
            exit 1
          }
          if [ "$state" != "shut off" ]; then
            touch /run/windows-vm-${engine.vmName}.backup-was-running
            ${config.services.windows-vm.scripts.stop}/bin/windows-vm-stop ${engine.vmName} 180
          fi
        ''
      ];
      cleanupCommands = [
        ''
          if [ -f /run/windows-vm-${engine.vmName}.backup-was-running ]; then
            rm -f /run/windows-vm-${engine.vmName}.backup-was-running
            ${config.services.windows-vm.scripts.start}/bin/windows-vm-start ${engine.vmName}
          fi
        ''
      ];
    };
  };
}
