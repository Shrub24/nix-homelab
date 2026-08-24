# Reusable Windows VM layer: declarative libvirt/KVM domains attached to the
# host-owned always-on bridge, loopback SPICE display, and virtiofs shares.
# Consumers (e.g. modules/applications/dj) define instances and wire
# locks/backup contracts; this module owns domain XML generation and
# lifecycle units, and only consumes the fleet-networking bridge that guests
# attach to — it never creates or owns physical networking.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.windows-vm;

  enabledInstances = lib.filterAttrs (_: inst: inst.enable) cfg.instances;

  ovmfCode = pkgs.OVMFFull.firmware; # store path string to OVMF_CODE.fd
  ovmfVarsTemplate = "${dirOf pkgs.OVMFFull.firmware}/OVMF_VARS.fd";

  instanceDir = name: "/var/lib/windows-vm/${name}";

  virsh = "${pkgs.libvirt}/bin/virsh";

  # Graceful ACPI shutdown with a bounded wait, then hard destroy as the
  # fallback. Used by ExecStop and by backup quiesce hooks so every stop path
  # has identical semantics. Takes the domain name as $1, wait seconds as $2.
  stopAndWait = pkgs.writeShellScriptBin "windows-vm-stop" ''
    set -euo pipefail
    dom="$1"
    timeout="''${2:-180}"
    ${virsh} shutdown "$dom" >/dev/null 2>&1 || true
    for ((i = 0; i < timeout; i++)); do
      state=$(${virsh} domstate "$dom" 2>/dev/null || echo unknown)
      if [[ "$state" == "shut off" ]]; then
        exit 0
      fi
      sleep 1
    done
    echo "windows-vm: '$dom' did not shut down within ''${timeout}s, destroying" >&2
    ${virsh} destroy "$dom" >/dev/null 2>&1 || true
    ${stopAndWaitWait}/bin/windows-vm-wait-shutoff "$dom" 30
  '';

  # Internal short wait used after destroy; split out so the public script
  # stays readable.
  stopAndWaitWait = pkgs.writeShellScriptBin "windows-vm-wait-shutoff" ''
    set -euo pipefail
    dom="$1"
    timeout="''${2:-120}"
    for ((i = 0; i < timeout; i++)); do
      state=$(${virsh} domstate "$dom" 2>/dev/null || echo unknown)
      if [[ "$state" == "shut off" ]]; then
        exit 0
      fi
      sleep 1
    done
    echo "windows-vm: timed out waiting for '$dom' shutoff" >&2
    exit 1
  '';

  startDomain = pkgs.writeShellScriptBin "windows-vm-start" ''
    set -euo pipefail
    # Idempotent: unit restarts (redeploys, activation retries) must not fail
    # when the domain is already up.
    state=$(${virsh} domstate "$1" 2>/dev/null || echo unknown)
    case "$state" in
      running | paused) exit 0 ;;
    esac
    ${virsh} start "$1"
  '';

  # Deterministic per-instance UUID: `virsh define` only updates an existing
  # domain when identity is stable; a fresh random UUID per render collides
  # with the previously defined one ("domain 'x' already exists with uuid").
  instanceUuid =
    name:
    let
      h = builtins.hashString "md5" "nix-homelab:windows-vm:${name}";
      version = "3"; # RFC 4122 version 3 (name-based MD5)
      variant = "b"; # RFC 4122 variant 10xx
    in
    builtins.substring 0 8 h
    + "-"
    + builtins.substring 8 4 h
    + "-"
    + version
    + builtins.substring 13 3 h
    + "-"
    + variant
    + builtins.substring 17 3 h
    + "-"
    + builtins.substring 20 12 h;

  shareXml =
    tag: share:
    ''
      <filesystem type="mount" accessmode="passthrough">
        <driver type="virtiofs" queue="1024"/>
        <source dir="${share.source}"/>
        <target dir="${tag}"/>
    ''
    + lib.optionalString share.readonly "        <readonly/>\n"
    + "      </filesystem>";

  tpmXml =
    inst:
    lib.optionalString inst.tpm ''
      <tpm model="tpm-crb">
        <backend type="emulator" version="2.0"/>
      </tpm>'';

  # installer=true renders the install-media variant: Windows ISO + virtio-win
  # driver ISO as CD-ROMs, CD-ROM-first boot. Presence of the media is decided
  # at unit start (prepareScript), not at eval time.
  domainXml =
    name: inst: installer:
    ''
      <domain type="kvm">
        <name>${name}</name>
        <uuid>${instanceUuid name}</uuid>
        <memory unit="MiB">${toString inst.memory}</memory>
        <vcpu placement="static">${toString inst.vcpu}</vcpu>''
    + "\n"
    # virtiofs requires guest RAM on shared pages: emit <memoryBacking> only
    # when the instance defines shares, since it forces all guest RAM onto
    # shared memory and must not be set unconditionally.
    + lib.optionalString (inst.shares != { }) ''
      <memoryBacking>
        <source type="memfd"/>
        <access mode="shared"/>
      </memoryBacking>
    ''
    + ''
      <os>
        <type arch="x86_64" machine="q35">hvm</type>
        <loader readonly="yes" type="pflash">${ovmfCode}</loader>
        <nvram template="${ovmfVarsTemplate}">${instanceDir name}/OVMF_VARS.fd</nvram>
        ${
          if installer then "<boot dev=\"cdrom\"/>\n          <boot dev=\"hd\"/>" else "<boot dev=\"hd\"/>"
        }
      </os>
      <features>
        <acpi/>
        <apic/>
        <hyperv mode="custom">
          <relaxed state="on"/>
          <vapic state="on"/>
          <spinlocks state="on" retries="8191"/>
        </hyperv>
      </features>
      <cpu mode="host-passthrough"/>
      <clock offset="localtime">
        <timer name="rtc" tickpolicy="catchup"/>
        <timer name="pit" tickpolicy="delay"/>
        <timer name="hpet" present="no"/>
        <timer name="hypervclock" present="yes"/>
      </clock>
      <on_poweroff>destroy</on_poweroff>
      <on_reboot>restart</on_reboot>
      <on_crash>destroy</on_crash>
      <devices>
        <disk type="file" device="disk">
          <driver name="qemu" type="qcow2"/>
          <source file="${inst.diskPath}"/>
          <target dev="vda" bus="virtio"/>
        </disk>''
    + lib.optionalString installer ''
      <disk type="file" device="cdrom">
        <driver name="qemu" type="raw"/>
        <source file="${inst.installDir}/install.iso"/>
        <target dev="sda" bus="sata"/>
        <readonly/>
      </disk>
      <disk type="file" device="cdrom">
        <driver name="qemu" type="raw"/>
        <source file="${inst.installDir}/virtio-win.iso"/>
        <target dev="sdb" bus="sata"/>
        <readonly/>
      </disk>''
    + "\n"
    + ''
      <interface type="bridge">
        <source bridge="${cfg.bridgeName}"/>
        <model type="virtio"/>
      </interface>
      ${lib.concatStringsSep "\n          " (lib.mapAttrsToList shareXml inst.shares)}
      <graphics type="spice" port="${toString inst.spicePort}" autoport="no" listen="127.0.0.1">
        <listen type="address" address="127.0.0.1"/>
      </graphics>
      <video>
        <model type="virtio"/>
      </video>
      <input type="tablet" bus="usb"/>
      <input type="keyboard" bus="usb"/>''
    + tpmXml inst
    + "\n"
    + ''
          <memballoon model="virtio"/>
        </devices>
      </domain>
    '';

  domainFile =
    name: pkgs.writeText "windows-vm-${name}.xml" (domainXml name enabledInstances.${name} false);

  domainInstallFile =
    name:
    pkgs.writeText "windows-vm-${name}-install.xml" (domainXml name enabledInstances.${name} true);

  # Per-instance ExecStartPre: create runtime dirs, seed OVMF vars once,
  # preallocate the system disk when missing. umask keeps guest disk images
  # (Windows profile data, library DB) root-only.
  #
  # Install mode is driven by the windows-vm-<name>-install command, which
  # stages media into installDir and restarts this unit; the presence pick
  # here is that command's plumbing. Installer mode lasts until the next
  # unit restart without media (--clear removes it explicitly).
  prepareScript =
    name: inst:
    pkgs.writeShellScript "windows-vm-${name}-prepare" ''
      set -euo pipefail
      umask 077
      install -d -m 0700 ${instanceDir name}
      [ -f ${instanceDir name}/OVMF_VARS.fd ] || install -m 0600 ${ovmfVarsTemplate} ${instanceDir name}/OVMF_VARS.fd
      [ -f ${inst.diskPath} ] || ${pkgs.qemu_kvm}/bin/qemu-img create -f qcow2 ${inst.diskPath} ${inst.diskSize}
      if [ -f ${inst.installDir}/install.iso ]; then
        [ -f ${inst.installDir}/virtio-win.iso ] || {
          echo "error: ${inst.installDir}/install.iso staged but virtio-win.iso missing (required for viostor during setup)" >&2
          exit 1
        }
        install -m 0600 ${domainInstallFile name} ${instanceDir name}/domain.xml
      else
        install -m 0600 ${domainFile name} ${instanceDir name}/domain.xml
      fi
      ${virsh} define ${instanceDir name}/domain.xml
    '';

  # Explicit install-lifecycle command: staging media + restarting the unit
  # enters installer mode; --clear removes the media and restarts back to
  # normal boot. The only supported interface for toggling install mode.
  installCommand =
    name: _:
    pkgs.writeShellScriptBin "windows-vm-${name}-install" ''
      set -euo pipefail
      dir=${enabledInstances.${name}.installDir}
      unit=windows-vm-${name}.service
      usage() {
        echo "usage: windows-vm-${name}-install <install.iso> <virtio-win.iso>" >&2
        echo "       windows-vm-${name}-install --clear    (exit installer mode)" >&2
        exit 2
      }
      if [ "''${1:-}" = "--clear" ]; then
        sudo rm -f "$dir/install.iso" "$dir/virtio-win.iso"
        sudo systemctl try-restart "$unit"
        echo "installer media removed; ${name} returns to normal boot"
        exit 0
      fi
      [ $# -eq 2 ] || usage
      for f in "$1" "$2"; do
        [ -f "$f" ] || { echo "error: not found: $f" >&2; exit 1; }
      done
      sudo install -d -m 0755 "$dir"
      # skip copy when the argument already is the staged file (idempotent re-run)
      [ "$1" -ef "$dir/install.iso" ] || sudo install -m 0444 "$1" "$dir/install.iso"
      [ "$2" -ef "$dir/virtio-win.iso" ] || sudo install -m 0444 "$2" "$dir/virtio-win.iso"
      sudo systemctl restart "$unit"
      echo "${name} redefined in installer mode (CD-ROM-first boot)"
    '';
in
{
  options.services.windows-vm = {
    enable = lib.mkEnableOption "declarative Windows VM layer (libvirt/KVM)";

    bridgeName = lib.mkOption {
      type = lib.types.str;
      default = "br0";
      description = "Name of the host-owned always-on bridge (fleet.networking.bridge) that guest LAN traffic attaches to. The VM layer only consumes this bridge; the host must declare it via the fleet networking aspect.";
    };

    instances = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Whether the ${name} instance is materialized.";
              };

              vcpu = lib.mkOption {
                type = lib.types.ints.positive;
                default = 4;
                description = "Virtual CPU count.";
              };

              memory = lib.mkOption {
                type = lib.types.ints.positive;
                default = 8192;
                description = "Guest memory in MiB.";
              };

              diskPath = lib.mkOption {
                type = lib.types.str;
                default = "${instanceDir name}/system.qcow2";
                description = "System disk image path (created on first start).";
              };

              diskSize = lib.mkOption {
                type = lib.types.str;
                default = "64G";
                description = "System disk size passed to qemu-img on first creation.";
              };

              autostart = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Start the domain at boot via the controller unit.";
              };

              spicePort = lib.mkOption {
                type = lib.types.port;
                default = 5900;
                description = "Loopback-bound SPICE TCP port (reach via SSH tunnel).";
              };

              tpm = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Emulated TPM 2.0 device (required for Windows 11).";
              };

              installDir = lib.mkOption {
                type = lib.types.str;
                default = "/srv/data/windows-vm/${name}";
                description = "Staging directory for install media, managed through the windows-vm-${name}-install command: staging install.iso switches the domain to installer mode (CD-ROM-first boot, virtio-win.iso attached as driver CD); --clear removes the media and returns to normal boot. No configuration change is involved.";
              };

              shares = lib.mkOption {
                type = lib.types.attrsOf (
                  lib.types.submodule {
                    options = {
                      source = lib.mkOption {
                        type = lib.types.str;
                        description = "Host directory exposed via virtiofs.";
                      };
                      readonly = lib.mkOption {
                        type = lib.types.bool;
                        default = false;
                        description = "Present the share read-only to the guest.";
                      };
                    };
                  }
                );
                default = { };
                description = "Virtiofs shares keyed by mount tag (the guest-visible share name).";
              };
            };
          }
        )
      );
      default = { };
      description = "Windows VM instances managed by this layer.";
    };

    scripts = {
      stop = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        description = "Graceful-stop helper (ACPI shutdown, bounded wait, destroy fallback); args: DOMAIN [TIMEOUT].";
      };
      start = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        description = "Domain start helper; arg: DOMAIN.";
      };
    };
  };

  config = lib.mkIf (cfg.enable && enabledInstances != { }) {
    assertions = [
      {
        assertion =
          (config ? fleet)
          && (config.fleet ? networking)
          && config.fleet.networking.bridge != null
          && config.fleet.networking.bridge.name == cfg.bridgeName;
        message = ''
          services.windows-vm requires a host-owned always-on bridge '${cfg.bridgeName}'
          when instances are enabled. The VM layer only consumes the bridge and never
          creates or owns physical networking (fleet networking aspect, D-043). Declare
          it on the host via fleet.networking.bridge, e.g.
          fleet.networking.bridge = { name = "${cfg.bridgeName}"; macAddress = "<uplink-mac>"; };
        '';
      }
      {
        assertion =
          lib.length (lib.unique (map (i: i.spicePort) (lib.attrValues enabledInstances)))
          == lib.length (lib.attrValues enabledInstances);
        message = "services.windows-vm instances must use unique spicePort values.";
      }
      {
        assertion = lib.all (n: builtins.match "[A-Za-z0-9._-]+" n != null) (
          lib.attrNames enabledInstances
        );
        message = "services.windows-vm instance names must match [A-Za-z0-9._-]+ (used in unit names and shell scripts).";
      }
    ];

    virtualisation.libvirtd.enable = true;
    virtualisation.libvirtd.qemu.swtpm.enable = lib.any (i: i.tpm) (lib.attrValues enabledInstances);
    # virtiofsd is required to start any domain with <filesystem> devices.
    virtualisation.libvirtd.qemu.vhostUserPackages = [ pkgs.virtiofsd ];

    services.windows-vm.scripts = {
      stop = stopAndWait;
      start = startDomain;
    };

    # Define (and redefine on config change) all instance domains. virsh
    # define is idempotent and updates persistent XML in place.
    systemd.services = {
      # Upstream sets restartIfChanged=false, so capability changes (swtpm
      # entering libvirtd's PATH) never apply on switch and TPM domains fail
      # to define against the stale daemon. Guests survive restarts because
      # libvirtd uses KillMode=process — only the daemon is replaced.
      libvirtd.restartIfChanged = lib.mkForce (lib.any (i: i.tpm) (lib.attrValues enabledInstances));
      windows-vm-setup = {
        description = "Define windows-vm libvirt domains";
        after = [ "libvirtd.service" ];
        wants = [ "libvirtd.service" ];
        wantedBy = [ "multi-user.target" ];
        restartTriggers = lib.concatMap (name: [
          (domainFile name)
          (domainInstallFile name)
        ]) (lib.attrNames enabledInstances);
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            name: _:
            let
              target = "${instanceDir name}/domain.xml";
            in
            ''
              install -d -m 0755 ${instanceDir name}
              install -m 0600 ${domainFile name} ${target}
              ${virsh} define ${target}
            ''
          ) enabledInstances
        );
      };
    }
    // lib.mapAttrs' (
      name: inst:
      lib.nameValuePair "windows-vm-${name}" {
        description = "Windows VM ${name} (libvirt controller)";
        after = [
          "windows-vm-setup.service"
          "network-online.target"
        ];
        wants = [
          "windows-vm-setup.service"
          "network-online.target"
        ];
        wantedBy = lib.optional inst.autostart "multi-user.target";
        # No restartTriggers: XML changes are redefined by windows-vm-setup
        # and apply at next guest boot. Bouncing a running Windows guest on
        # every deploy would be hostile; restarting the controller unit is
        # an explicit operator action.
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # Must exceed the worst-case stopAndWait (180s) plus destroy
          # fallback (30s) or systemd kills the stop script mid-wait and
          # the unit state diverges from the actual domain state.
          TimeoutStopSec = 240;
          ExecStartPre = prepareScript name inst;
          ExecStart = "${startDomain}/bin/windows-vm-start ${name}";
          ExecStop = "${stopAndWait}/bin/windows-vm-stop ${name}";
        };
      }
    ) enabledInstances;

    systemd.tmpfiles.rules = map (name: "d ${enabledInstances.${name}.installDir} 0755 root root - -") (
      lib.attrNames enabledInstances
    );

    environment.systemPackages = [
      stopAndWait
      startDomain
      pkgs.virt-viewer
    ]
    ++ lib.mapAttrsToList installCommand enabledInstances;
  };
}
