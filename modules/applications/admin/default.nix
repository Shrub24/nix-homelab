{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.applications.admin;
  globals = import ../../../policy/globals.nix;
  secretHelpers = import ../../../lib/secrets.nix { inherit lib; };
  identityPolicy = builtins.fromJSON (builtins.readFile ../../../policy/identity.json);
  oauth2Policy = identityPolicy.systems.oauth2;

  termixRoute = cfg.policyServices.${oauth2Policy.termix.routeKey};
  quantumRoute = cfg.policyServices.${oauth2Policy.quantum.routeKey};

  oidcRuntimeEnabled =
    clientPolicy:
    if clientPolicy ? routeKey then
      cfg.policyServices.${clientPolicy.routeKey}.access.oidc.enabled
    else
      true;

in
{
  imports = [
    ../../shared/identity-oidc.nix
    ../../services/admin/termix.nix
    ../../services/admin/kanidm.nix
    ../../services/admin/cockpit.nix
    ../../services/admin/webhook.nix
    ../../services/admin/gatus.nix
    ../../services/admin/vaultwarden.nix
    ../../services/admin/quantum.nix
    ../../services/admin/homepage/default.nix
    ../../services/admin/beszel.nix
  ];

  options.applications.admin = {
    enable = lib.mkEnableOption "admin application composition";

    dataRoot = lib.mkOption {
      type = lib.types.str;
      default = globals.applications.admin.dataRoot;
      description = "Top-level data root for admin application services.";
    };

    policyServices = lib.mkOption {
      type = lib.types.attrs;
      default = lib.attrByPath [ "repo" "web" "currentHost" "services" ] { } config;
      description = "Resolved host services from policy/web-services.nix for SSOT endpoint consumption.";
    };

    secretFiles.host = secretHelpers.mkSecretFileOption "admin-host-secrets";
    secretFiles.identity = secretHelpers.mkSecretFileOption "admin-identity-secrets";
    secretFiles.identityProvisioning = secretHelpers.mkSecretFileOption "admin-identity-provisioning";
    secretFiles.oidcClients = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = "Per-client OIDC secret source files keyed by Kanidm oauth2 client id.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # Base config with assertions and default service enables
      {
        services.identity.oidc = {
          providerUrl = cfg.policyServices."kanidm-admin".publicUrl;
        };

        assertions = [
          (secretHelpers.mkRequiredSecretAssertion {
            enable = cfg.enable;
            file = cfg.secretFiles.host;
            feature = "applications.admin";
            label = "secretFiles.host";
          })
        ];

        services.admin.termix.enable = lib.mkDefault true;
        services.admin.kanidm.enable = lib.mkDefault true;
        services.admin.cockpit.enable = lib.mkDefault true;
        services.admin.webhook.enable = lib.mkDefault true;
        services.admin.gatus.enable = lib.mkDefault true;
        services.admin.vaultwarden.enable = lib.mkDefault true;
        services.admin.quantum.enable = lib.mkDefault false;
        services.admin.homepage.enable = lib.mkDefault true;
        services.admin.beszel.enable = lib.mkDefault true;
      }

      # Pass-through: propagate secretFiles to sub-services
      {
        services.admin.vaultwarden.secretFiles.host = cfg.secretFiles.host;
        services.admin.homepage.secretFiles.host = cfg.secretFiles.host;
        services.admin.quantum.secretFiles.host = cfg.secretFiles.host;
        services.admin.kanidm.secretFiles.identity = cfg.secretFiles.identity;
        services.admin.kanidm.secretFiles.provisioning = cfg.secretFiles.identityProvisioning;
        services.admin.kanidm.secretFiles.oauth2Clients = cfg.secretFiles.oidcClients;
      }

      # All host-level secrets - from host-scoped secret file
      {
        sops.secrets = secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
          admin_ssh_identity = {
            key = "admin/ssh/identity";
            path = "/run/secrets/admin.ssh.identity";
            owner = "root";
            group = "root";
          };
          admin_ssh_known_hosts = {
            key = "admin/ssh/known_hosts";
            path = "/run/secrets/admin.ssh.known_hosts";
            owner = "root";
            group = "root";
          };
        };
      }

      # Admin data root tmpfiles and ACL
      {
        systemd.tmpfiles.rules = [
          "d ${cfg.dataRoot} 0755 root root - -"
          "z ${cfg.dataRoot} 0755 root root - -"
          "a+ ${cfg.dataRoot} - - - - user:dev:r-X"
          "a+ ${cfg.dataRoot} - - - - default:user:dev:r-X"
        ];

        systemd.services.admin-dev-data-access-reconcile = {
          description = "Reconcile dev read/traverse access on admin data root";
          wantedBy = [ "multi-user.target" ];
          after = [ "systemd-tmpfiles-setup.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "admin-dev-data-access-reconcile" ''
              set -euo pipefail
              if [ -d "${cfg.dataRoot}" ]; then
                ${pkgs.acl}/bin/setfacl -m u:dev:rX "${cfg.dataRoot}"
                find "${cfg.dataRoot}" -xdev -type d ! -path "${cfg.dataRoot}/quantum/mnt" ! -path "${cfg.dataRoot}/quantum/mnt/*" -exec ${pkgs.acl}/bin/setfacl -m d:u:dev:rX {} +
              fi
            '';
          };
        };
      }

      (lib.mkIf config.services.admin.kanidm.enable {
        services.admin.kanidm = {
          dataDir = "${cfg.dataRoot}/kanidm";
          appUrl = cfg.policyServices."kanidm-admin".publicUrl;
          tlsChainFile = "/var/lib/acme/${cfg.policyServices."kanidm-admin".primaryDomain}/fullchain.pem";
          tlsKeyFile = "/var/lib/acme/${cfg.policyServices."kanidm-admin".primaryDomain}/key.pem";
          tlsReaderGroups = [ "caddy" ];
        };
      })

      # Termix OIDC and Tailscale serve
      (lib.mkIf config.services.admin.termix.enable {
        services.admin.termix = {
          dataDir = "${cfg.dataRoot}/termix";
          secretFiles.oidc = cfg.secretFiles.oidcClients.termix;
          oidc = {
            enabled = oidcRuntimeEnabled oauth2Policy.termix;
            clientId = config.services.identity.oidc.clients.termix.clientId;
            issuerUrl = config.services.identity.oidc.clients.termix.issuerUrl;
            authorizationUrl = config.services.identity.oidc.clients.termix.authorizationUrl;
            tokenUrl = config.services.identity.oidc.clients.termix.tokenUrl;
            userinfoUrl = config.services.identity.oidc.clients.termix.userinfoUrl;
            environmentFile =
              if oidcRuntimeEnabled oauth2Policy.termix then
                config.sops.templates."termix-oidc.env".path
              else
                null;
          };
        };

        services.state-backups.services.termix = {
          enable = true;
          mode = "live";
          paths = [ "${cfg.dataRoot}/termix" ];
        };

        systemd.services.tailscale-serve-termix = {
          description = "Expose Termix via dedicated Tailscale HTTPS port";
          requires = [
            "tailscaled.service"
            "podman-termix.service"
          ];
          wants = [
            "tailscaled-autoconnect.service"
            "tailscaled.service"
            "podman-termix.service"
          ];
          after = [
            "tailscaled-autoconnect.service"
            "tailscaled.service"
            "podman-termix.service"
          ];
          partOf = [
            "tailscaled.service"
            "podman-termix.service"
          ];
          restartIfChanged = true;
          stopIfChanged = true;
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = ''
              ${pkgs.tailscale}/bin/tailscale serve --yes --bg --https=8443 ${termixRoute.upstream}
            '';
            ExecStop = ''
              ${pkgs.tailscale}/bin/tailscale serve --https=8443 off
            '';
          };
        };
      })

      # Quantum OIDC configuration
      (lib.mkIf config.services.admin.quantum.enable {
        services.admin.quantum = {
          secretFiles.oidc = cfg.secretFiles.oidcClients.quantum;
          oidc = {
            enabled = oidcRuntimeEnabled oauth2Policy.quantum;
            issuerUrl = config.services.identity.oidc.clients.quantum.issuerUrl;
            clientId = config.services.identity.oidc.clients.quantum.clientId;
            environmentFile =
              if oidcRuntimeEnabled oauth2Policy.quantum then
                config.sops.templates."quantum-oidc.env".path
              else
                null;
          };
        };
      })
    ]
  );
}
