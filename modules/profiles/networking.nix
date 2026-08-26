# Native systemd-networkd networking aspect (import-activated).
#
# Importing this module activates the aspect: the host owns its physical
# networking through native `systemd.network` units derived from the
# `fleet.networking` host facts, and the legacy scripted/dhcpcd backend is
# disabled. There is no top-level enable flag.
#
# Hosts contribute facts only:
#   fleet.networking.uplink.interface = "eno1";   # required
#   fleet.networking.uplink.ipv6AcceptRA = false; # optional (providers without IPv6)
#   fleet.networking.bridge = { name = "br0"; macAddress = ".."; }; # optional
#   fleet.networking.dns.servers = [ "1.1.1.1" "8.8.8.8" ]; # optional (null = DHCP-only)
#
# See openspec/changes/adopt-native-systemd-networkd/design.md (D1-D5).
{
  config,
  lib,
  ...
}:
let
  cfg = config.fleet.networking;
  # The addressed, routed interface: the uplink when unbridged, otherwise the
  # bridge (member uplink carries no addressing).
  addressed = if cfg.bridge != null then cfg.bridge.name else cfg.uplink.interface;
in
{
  options.fleet.networking = {
    uplink = {
      interface = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Physical uplink interface owned by this host (required host fact).
        '';
      };
      ipv6AcceptRA = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = ''
          IPv6AcceptRA override for the addressed interface. null keeps the
          upstream default; set false on providers that do not allocate IPv6
          to prevent surprise autoconfiguration.
        '';
      };
    };
    bridge = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Bridge interface name.";
            };
            macAddress = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Pinned MAC address for the bridge netdev. Required when a bridge
                is declared so the bridge presents the physical NIC identity and
                DHCP reservations survive the backend migration.
              '';
            };
          };
        }
      );
      default = null;
      description = ''
        Optional always-on bridge topology. When declared, the member uplink
        carries no addressing and the bridge becomes the addressed, routed
        uplink, independent of which applications consume it.
      '';
    };
    dns = {
      servers = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        default = null;
        description = ''
          Global DNS servers pinned via systemd-resolved. When non-null, the
          aspect sets resolved's global DNS from this fact. When null (the
          default), the aspect leaves resolved's global DNS to nixpkgs
          defaults (config.networking.nameservers), so per-link DHCP/provider
          DNS stays primary unless a host also sets networking.nameservers.
        '';
      };
    };
  };

  config = {
    # Native networkd backend; legacy scripted networking and dhcpcd disabled.
    # mkDefault so a host's plain/forced legacy `true` wins the merge and is
    # then rejected by the curated assertions below instead of a generic
    # equal-priority conflict.
    systemd.network.enable = true;
    networking.useDHCP = lib.mkDefault false;
    networking.dhcpcd.enable = lib.mkDefault false;

    # nixos-facter's detected-DHCP module force-enables networking.useDHCP on
    # hosts with a facter report, colliding with the aspect's ownership. The
    # aspect owns physical networking; hardware facts stay wired. Plain
    # priority so it beats facter's own mkDefault.
    hardware.facter.detected.dhcp.enable = false;

    # Resolver mechanism fleet-wide: systemd-resolved with safe defaults.
    # Per-link DHCP DNS stays primary; global DNS is pinned only when the
    # host declares dns.servers; FallbackDNS provides resilience.
    services.resolved.enable = true;
    services.resolved.settings.Resolve = {
      DNSOverTLS = lib.mkDefault "opportunistic";
      DNSSEC = lib.mkDefault "allow-downgrade";
      FallbackDNS = lib.mkDefault [
        "1.1.1.1"
        "8.8.8.8"
      ];
    };
    services.resolved.settings.Resolve.DNS = lib.mkIf (cfg.dns.servers != null) cfg.dns.servers;

    assertions = [
      {
        assertion = cfg.uplink.interface != null;
        message = ''
          fleet.networking.uplink.interface is a required host fact: the networking
          aspect must know which physical interface is the uplink. Declare it in the
          host config, e.g. fleet.networking.uplink.interface = "ens18";
        '';
      }
      {
        assertion = cfg.bridge == null || cfg.bridge.macAddress != null;
        message = ''
          fleet.networking.bridge.macAddress is required when fleet.networking.bridge
          is declared: the bridge must present the physical NIC's pinned MAC so DHCP
          reservations survive (design D3). Set it, e.g.
          fleet.networking.bridge.macAddress = "84:a9:3e:6b:94:44";
        '';
      }
      {
        assertion = !config.networking.useDHCP;
        message = ''
          networking.useDHCP = true conflicts with the fleet networking aspect (native
          systemd.network). Remove networking.useDHCP and rely on the aspect's DHCPv4
          units instead.
        '';
      }
      {
        assertion = !config.networking.dhcpcd.enable;
        message = ''
          networking.dhcpcd.enable = true conflicts with the fleet networking aspect
          (native systemd.network). Remove it so dhcpcd and networkd do not fight over
          the same interfaces.
        '';
      }
      {
        assertion = !config.networking.useNetworkd;
        message = ''
          networking.useNetworkd = true (the translation shim) conflicts with the fleet
          networking aspect, which emits native systemd.network units directly. Do not
          set networking.useNetworkd.
        '';
      }
    ];

    # Exact-match units only: unbridged uplink or bridged member + addressed
    # bridge. Virtual/overlay interfaces (Podman, tailscale0, veth, libvirt)
    # are unmanaged by construction.
    systemd.network.networks = lib.mkIf (cfg.uplink.interface != null) (
      {
        ${addressed} = {
          matchConfig.Name = addressed;
          networkConfig = {
            DHCP = "ipv4";
          }
          // lib.optionalAttrs (cfg.uplink.ipv6AcceptRA != null) {
            IPv6AcceptRA = cfg.uplink.ipv6AcceptRA;
          };
          dhcpV4Config.ClientIdentifier = "mac";
          linkConfig.RequiredForOnline = "routable";
        };
      }
      // lib.optionalAttrs (cfg.bridge != null) {
        # Bridge member: no addressing, enslaved to the bridge.
        ${cfg.uplink.interface} = {
          matchConfig.Name = cfg.uplink.interface;
          networkConfig.Bridge = cfg.bridge.name;
          linkConfig.RequiredForOnline = "enslaved";
        };
      }
    );

    systemd.network.netdevs = lib.mkIf (cfg.bridge != null) {
      ${cfg.bridge.name} = {
        netdevConfig = {
          Name = cfg.bridge.name;
          Kind = "bridge";
        }
        // lib.optionalAttrs (cfg.bridge.macAddress != null) {
          MACAddress = cfg.bridge.macAddress;
        };
      };
    };
  };
}
