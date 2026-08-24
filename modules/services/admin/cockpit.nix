{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.admin.cockpit;
  svcUser = cfg.serviceUser;
  hasCockpitPublicHost = lib.hasAttrByPath [
    "applications"
    "admin"
    "policyServices"
    "cockpit-admin"
    "publicHost"
  ] config;
  cockpitPublicHost =
    if cfg.publicHost != null then
      cfg.publicHost
    else if hasCockpitPublicHost then
      config.applications.admin.policyServices."cockpit-admin".publicHost
    else
      null;
  cockpitUrlRoot =
    if cfg.urlRoot != null then
      cfg.urlRoot
    else if hasCockpitPublicHost then
      config.applications.admin.policyServices."cockpit-admin".path
    else
      "/";
in
{
  imports = [
    ./cockpit/loopback-tls.nix
    ./cockpit/tailscale-serve.nix
  ];

  options.services.admin.cockpit = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable admin-owned Cockpit module wiring.";
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
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable a minimal dedicated Cockpit-only service account.";
      };

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

  config = lib.mkIf cfg.enable {
    services.cockpit = {
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

    # Keep cockpit socket bind explicit/IPv4-only and reset inherited
    # ListenStream entries to avoid ambiguous/wildcard address-family binds.
    systemd.sockets.cockpit.listenStreams = lib.mkForce [
      ""
      "${cfg.listenAddress}:${toString config.services.cockpit.port}"
    ];
    systemd.sockets.cockpit.socketConfig.FreeBind = true;

    environment.systemPackages = [
      pkgs."cockpit-podman"
      pkgs."cockpit-files"
    ];

    services.udisks2.enable = true;

    users.users = lib.optionalAttrs svcUser.enable {
      "${svcUser.name}" = {
        isNormalUser = true;
        description = "Restricted Cockpit service account";
        shell = "${pkgs.bashInteractive}/bin/bash";
        hashedPasswordFile = svcUser.hashedPasswordFile;
      };
    };

    services.openssh.extraConfig = lib.mkIf svcUser.enable (
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

    assertions = [
      {
        assertion = !svcUser.enable || svcUser.hashedPasswordFile != null;
        message = "Set services.admin.cockpit.serviceUser.hashedPasswordFile when serviceUser.enable=true.";
      }
    ];
  };
}
