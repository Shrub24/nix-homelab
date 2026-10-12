# Networking foundation aspect: selecting it is its enablement. The native
# systemd-networkd contract is owned here: units are derived from the
# `fleet.networking` host facts, and the scripted/dhcpcd backend is disabled.
_: {
  flake.modules.nixos.networking =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.fleet.networking;
      globals = import ../../policy/globals.nix;
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
        systemd.network = {
          enable = true;

          # Exact-match units only; Podman, tailscale0, veth and libvirt stay
          # unmanaged by construction.
          networks = lib.mkMerge [
            {
              # Exists from boot, independent of any Podman network.
              ${globals.serviceNetwork.interface} = {
                matchConfig.Name = globals.serviceNetwork.interface;
                address = [
                  "${globals.serviceNetwork.address}/${toString globals.serviceNetwork.prefixLength}"
                ];
                linkConfig.RequiredForOnline = false;
              };
            }
            (lib.mkIf (cfg.uplink.interface != null) (
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
            ))
          ];

          netdevs = lib.mkMerge [
            {
              ${globals.serviceNetwork.interface} = {
                netdevConfig = {
                  Name = globals.serviceNetwork.interface;
                  Kind = "dummy";
                };
              };
            }
            (lib.mkIf (cfg.bridge != null) {
              ${cfg.bridge.name} = {
                netdevConfig = {
                  Name = cfg.bridge.name;
                  Kind = "bridge";
                }
                // lib.optionalAttrs (cfg.bridge.macAddress != null) {
                  MACAddress = cfg.bridge.macAddress;
                };
              };
            })
          ];
        };
        networking.useDHCP = lib.mkDefault false;
        networking.dhcpcd.enable = lib.mkDefault false;

        # The same name resolves on the host, so host-side dialers use it too.
        networking.hosts = {
          "${globals.serviceNetwork.address}" = [ globals.serviceNetwork.hostName ];
        };

        # Containers resolve the tailnet's short names. This is the only DNS
        # default worth adding: `dns_servers` would override podman's per-network
        # resolver and break container-to-container names.
        virtualisation.containers.containersConf.settings.containers.dns_searches = [
          globals.tailnet.suffix
        ];

        # nixos-facter's detected-DHCP module force-enables networking.useDHCP on
        # hosts with a facter report, colliding with the aspect's ownership. The
        # aspect owns physical networking; hardware facts stay wired. Plain
        # priority so it beats facter's own mkDefault.
        hardware.facter.detected.dhcp.enable = false;

        # Resolver mechanism fleet-wide: systemd-resolved with safe defaults.
        # Per-link DHCP DNS stays primary; global DNS is pinned only when the
        # host declares dns.servers; FallbackDNS provides resilience.
        services.resolved = {
          enable = true;
          settings.Resolve = {
            DNSOverTLS = lib.mkDefault "opportunistic";
            DNSSEC = lib.mkDefault "allow-downgrade";
            FallbackDNS = lib.mkDefault [
              "1.1.1.1"
              "8.8.8.8"
            ];
            DNS = lib.mkIf (cfg.dns.servers != null) cfg.dns.servers;
          };
        };

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
      };
    };
}
