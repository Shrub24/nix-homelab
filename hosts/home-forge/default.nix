{
  lib,
  config,
  ...
}:
let
  hasHostSecrets = builtins.pathExists ../../secrets/hosts/home-forge/system.yaml;
in
{
  imports = [
    ../../modules/profiles/base-server.nix
    ../../modules/profiles/fleet-standard.nix
    ../../modules/profiles/networking.nix
    ../../modules/shared/web-policy.nix
    # Hard dependency of base-server (via state-backups): declares
    # services.notification-daemon option. Infrastructure, not a workload.
    ../../modules/services/notification-daemon
    ../../modules/storage/disko-two-disk.nix
    ../../modules/core/users.nix
    ../../modules/applications/dj
  ];

  networking.hostName = "home-forge";

  # Locally-managed physical host: plain LAN DHCP via native systemd-networkd
  # (fleet networking aspect), no static addresses and no public ingress. The
  # always-on br0 bridge over eno1 presents the pinned NIC MAC so the router
  # reservation survives; DNS is pinned to public resolvers for a private
  # network with no local split-horizon.
  fleet.networking = {
    uplink.interface = "eno1";
    bridge = {
      name = "br0";
      macAddress = "84:a9:3e:6b:94:44";
    };
    dns.servers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
  };

  # UEFI + systemd-boot. The shared base (core/base.nix) defines GRUB as plain
  # definitions; switch the loader implementation only and keep the base EFI
  # policy (canTouchEfiVariables = false — do not touch NVRAM). Secure Boot off
  # for this unencrypted local-workstation baseline.
  boot.loader = {
    grub.enable = lib.mkForce false;
    systemd-boot.enable = true;
  };

  # Two-disk layout: ESP + ext4 root on the NVMe; ext4 /srv/storage on the
  # HDD. Devices captured from the live-ISO /dev/disk/by-id at gate 8.1.
  # LAN: eno1 84:a9:3e:6b:94:44 (DHCP + router reservation).
  disko.devices.disk.main.device = "/dev/disk/by-id/nvme-SAMSUNG_MZVLB1T0HBLR-000H1_S4GRNX0RA26985";
  # Oversized ESP: room for future boot entries plus a backup copy of the
  # existing ESP contents.
  disko-esp-size = "4G";
  disko-second-disk = "/dev/disk/by-id/ata-ST1000DM010-2EP102_ZN19040F";

  # Tailscale is enabled by base-server. Authentication only activates once host
  # secrets exist (two-step sops bootstrap). The tag:homelab posture comes from
  # the operator-provided auth key at the secret gate; the host does not
  # advertise a per-host tag.
  services.tailscale = lib.mkIf hasHostSecrets {
    authKeyFile = "/run/secrets/tailscale.auth_key";
  };

  sops.defaultSopsFile = ../../secrets/common.yaml;
  sops.secrets = lib.optionalAttrs hasHostSecrets {
    tailscale_auth_key = {
      sopsFile = ../../secrets/hosts/home-forge/system.yaml;
      key = "tailscale/auth_key";
      path = "/run/secrets/tailscale.auth_key";
      mode = "0400";
    };
  };

  # Host-scoped recovery baseline (HFG-7): rescue operator + recurring reboot
  # exercise. The physical/supplier console is the PRIMARY break-glass path;
  # the rescue operator is defense-in-depth. Activates once host secrets exist.
  services.hostRecovery = lib.mkIf hasHostSecrets {
    enable = true;
    secretFile = ../../secrets/hosts/home-forge/system.yaml;
    rescueUser.name = "rescue";
    reboot.onCalendar = "weekly";
  };

  # Host-scoped R2/restic backup (HFG-6): core/high-level system state only
  # (config, host identity, recovery material); workload-specific paths are
  # added as workloads are introduced, not speculatively. Credentials resolve
  # from the host system secret. Activates once host secrets exist.
  services.state-backups = lib.mkIf hasHostSecrets {
    enable = true;
    secretFile = ../../secrets/hosts/home-forge/system.yaml;
    bucket = "shrublab-backup-home-forge";
    stagingRoot = "/srv/data/state-backups";
    # Baseline-only host: no workload modules contribute backup contracts
    # yet, so back up the persistent host identity directly. Workload paths
    # are added as workloads are introduced.
    services.host-core.paths = [ "/etc/ssh" ];
  };

  # nixos-facter facts replace a hand-written hardware-configuration.nix. The
  # report was captured from the live ISO (operator gate 8.3); until then keep
  # facter wired but inert so base-install eval converges without the file.
  hardware.facter.reportPath = lib.mkIf (builtins.pathExists ./facter.json) ./facter.json;
  # 32 GB RAM: raise the /build tmpfs cap from the base-server default (8G)
  # so large remote builds don't run out of space.
  fileSystems."/build".options = lib.mkForce [
    "size=50%"
    "mode=0755"
  ];

  services.notification-daemon = {
    enable = true;
    secretFiles.host = ../../secrets/services/notification-daemon.yaml;
    secretFiles.hostSystem = ../../secrets/hosts/home-forge/system.yaml;
    ntfy.enable = true;
  };

  # Engine DJ on a Windows VM: library DB on /srv/data/engine-dj/library,
  # music shared read-only from the bulk disk, SC6000 reachable over the
  # eno1 bridge. Guest installation runs through the
  # windows-vm-windows-dj-install command (runbook); config never changes
  # for the install lifecycle.
  applications.dj = {
    enable = true;
    engine.enable = true;
  };

  system.stateVersion = "25.11";
}
