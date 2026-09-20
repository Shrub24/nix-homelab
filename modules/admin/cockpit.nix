# Cockpit deployment aspect: selection imports the leaf (whose `enable` default
# is true) and owns the wiring common to every host — the dedicated service user
# and the service-user secret registration. Host variants stay explicit:
# `publicHost`/`urlRoot` and `loopbackTls.enable` are host-local.
{ ... }:
{
  flake.modules.nixos.cockpit =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      hostSecretFile = ../../secrets/hosts + "/${config.networking.hostName}/system.yaml";
      hasHostSecrets = builtins.pathExists hostSecretFile;

      cfg = config.services.admin.cockpit;
      svcUser = cfg.serviceUser;

      webServices = config.repo.web.currentHost.services or { };
      cockpitRoute =
        if webServices ? "cockpit-admin" then
          webServices."cockpit-admin"
        else
          throw "cockpit: required canonical web-policy route 'repo.web.currentHost.services.\"cockpit-admin\"' is missing for host '${
            config.networking.hostName or "?"
          }'";

      cockpitPublicHost = if cfg.publicHost != null then cfg.publicHost else cockpitRoute.publicHost;
      cockpitUrlRoot = if cfg.urlRoot != null then cfg.urlRoot else cockpitRoute.path;
    in
    {
      options.services.admin.cockpit = {
        enable = lib.mkOption {
          type = lib.types.bool;
          # Default on: the aspect selection is the enablement and the leaf has
          # no other activation path.
          default = true;
          description = "Enable the Cockpit module wiring.";
        };

        listenAddress = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Address Cockpit socket listens on for this host.";
        };

        publicHost = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Public host used for Cockpit WebService origin settings when this host is published behind a reverse proxy.";
        };

        urlRoot = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Cockpit WebService UrlRoot for this host when published under a non-root path.";
        };

        serviceUser = {
          enable = lib.mkEnableOption "the dedicated Cockpit-only service account";

          name = lib.mkOption {
            type = lib.types.str;
            default = "cockpit-svc";
            description = "Username for the dedicated Cockpit service account.";
          };

          hashedPasswordFile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Path to a hashed password file for the Cockpit service account.";
          };

          denySsh = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Deny direct SSH access for the Cockpit service account.";
          };
        };

        loopbackTls = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate and install host-local CA-signed Cockpit loopback TLS material for trusted local HTTPS proxying.";
          };

          stateDir = lib.mkOption {
            type = lib.types.str;
            default = "/var/lib/cockpit-loopback-tls";
            description = "Persistent directory holding generated Cockpit loopback CA and leaf certificate material.";
          };

          serverName = lib.mkOption {
            type = lib.types.str;
            default = "localhost";
            description = "Primary DNS SAN used for the generated Cockpit loopback certificate.";
          };
        };

        tailscaleServe = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Expose Cockpit through a dedicated Tailscale Serve HTTPS endpoint for this host.";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = 9443;
            description = "Tailscale Serve HTTPS port used for Cockpit on this host.";
          };
        };
      };
      config = lib.mkMerge [
        (lib.mkIf cfg.enable {
          services = {
            cockpit = {
              enable = true;
              openFirewall = false;
              package = pkgs.cockpit;
              settings = lib.optionalAttrs (cockpitPublicHost != null) {
                WebService = {
                  Origins = lib.mkForce "https://${cockpitPublicHost} wss://${cockpitPublicHost}";
                  ProtocolHeader = "X-Forwarded-Proto";
                  ForwardedForHeader = "X-Forwarded-For";
                  LoginTo = false;
                }
                // lib.optionalAttrs (cockpitUrlRoot != "/") {
                  UrlRoot = cockpitUrlRoot;
                };
              };
            };

            udisks2.enable = true;

            openssh.extraConfig = lib.mkIf svcUser.enable (
              lib.mkAfter (
                if svcUser.denySsh then
                  ''
                    Match User ${svcUser.name}
                      PasswordAuthentication no
                      KbdInteractiveAuthentication no
                      PubkeyAuthentication no
                      PermitTTY no
                      X11Forwarding no
                      AllowTcpForwarding no
                      PermitTunnel no
                      ForceCommand /run/current-system/sw/bin/false
                  ''
                else
                  ''
                    Match User ${svcUser.name}
                      PasswordAuthentication yes
                      KbdInteractiveAuthentication yes
                      PubkeyAuthentication no
                  ''
              )
            );
          };

          # Keep cockpit socket bind explicit/IPv4-only and reset inherited
          # ListenStream entries to avoid ambiguous/wildcard address-family binds.
          systemd.sockets.cockpit = {
            listenStreams = lib.mkForce [
              ""
              "${cfg.listenAddress}:${toString config.services.cockpit.port}"
            ];
            socketConfig.FreeBind = true;
          };

          environment.systemPackages = [
            pkgs."cockpit-podman"
            pkgs."cockpit-files"
          ];

          users.users = lib.optionalAttrs svcUser.enable {
            "${svcUser.name}" = {
              isNormalUser = true;
              description = "Restricted Cockpit service account";
              shell = "${pkgs.bashInteractive}/bin/bash";
              inherit (svcUser) hashedPasswordFile;
            };
          };

          assertions = [
            {
              assertion = !svcUser.enable || svcUser.hashedPasswordFile != null;
              message = "Set services.admin.cockpit.serviceUser.hashedPasswordFile when serviceUser.enable=true.";
            }
          ];
        })
        ({
          services.admin.cockpit = {
            serviceUser = {
              enable = true;
              name = "cockpit-svc";
              hashedPasswordFile = config.sops.secrets.cockpit_service_user_password_hash.path;
            };

            tailscaleServe.enable = true;
          };

          sops.secrets = lib.optionalAttrs hasHostSecrets {
            cockpit_service_user_password_hash = {
              sopsFile = hostSecretFile;
              key = "cockpit/service_user/password_hash";
              path = "/run/secrets/cockpit.service_user.password_hash";
              owner = "root";
              group = "root";
              mode = "0400";
            };
          };
        })
      ];
    };
}
