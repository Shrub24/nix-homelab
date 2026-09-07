# Engine DJ library hosting on a Windows VM; guest setup is operator-driven
# (docs/runbooks/engine-dj-guest-setup.md).
{
  lib,
  config,
  pkgs,
  self,
  ...
}:
let
  cfg = config.applications.dj;
  inherit (cfg) engine;

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

      sharePath = lib.mkOption {
        type = lib.types.str;
        description = "Root exported to the guest (drive M:). Required; injected by the caller.";
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
    users.groups.music-ingest.gid = lib.mkDefault 990;

    services = {
      windows-vm = {
        enable = true;
        instances.${engine.vmName} = {
          inherit (engine) vcpu spicePort;
          memory = engine.memoryGiB * 1024;
          tpm = true; # Windows 11 installer requires emulated TPM 2.0
          shares = {
            media = {
              source = engine.sharePath;
              readonly = false;
            };
            # A cross-device submount inside M: breaks WinFsp readdir; use L:
            # with a guest junction instead (setup.ps1).
            engine-library = {
              source = engine.libraryPath;
              readonly = false;
            };
            setup = {
              source = "${self.packages.${pkgs.stdenv.hostPlatform.system}.windows-dj-setup}";
              readonly = true;
            };
          };
        };
      };

      # Quiesce contract: stop the VM only if it was running; the M:-drive
      # library rides along cold via the media backup in the same window.
      state-backups.services.engine-dj = {
        enable = true;
        mode = "quiesce";
        paths = [ engine.libraryPath ];
        prepareCommands = [
          ''
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

    systemd = {
      # Linux-side writers bind this target to inherit mutual exclusion with the VM.
      targets.dj-library-writers = {
        description = "Engine DJ library Linux-side writers (mutually exclusive with ${vmUnit})";
      };
      services = {
        "windows-vm-${engine.vmName}".conflicts = [ "dj-library-writers.target" ];
        restic-backups-state.conflicts = [ "dj-library-writers.target" ];
      };
      tmpfiles.rules = [
        "d ${engine.libraryPath} 0755 root root - -"
        "d ${engine.sharePath} 2770 root music-ingest - -"
      ];
    };
  };
}
