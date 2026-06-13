{
  lib,
  config,
  pkgs,
  ociImages,
  ...
}:
let
  appCfg = config.applications.admin;
  cfg = config.services.admin.quantum;
  quantumRoute = appCfg.policyServices."quantum-admin";
  listenAddress = quantumRoute.origin.host;
  listenPort = quantumRoute.origin.port;
  secretHelpers = import ../../../lib/secrets.nix { inherit lib; };

  mountRoot = "${appCfg.dataRoot}/quantum/mnt";
  mountPathFor = host: "${mountRoot}/${host.name}";

  localSourceMaskDir = "${appCfg.dataRoot}/quantum/local-source-mask";
  localSourceBindPath = "/srv/data";
  localSourceMaskPath = "${localSourceBindPath}/quantum/mnt";

  quantumSources =
    lib.optionals cfg.managedSourceEnabled [
      {
        name = "Local Files";
        path = "/srv";
        config.defaultEnabled = true;
      }
    ]
    ++ map (source: {
      name = source.name;
      path = source.path;
      config.defaultEnabled = true;
    }) cfg.localSources
    ++ map (host: {
      name = host.name;
      path = "/mnt/hosts/${host.name}";
      config.defaultEnabled = true;
    }) cfg.sftp.hosts;

  quantumConfig = {
    auth.methods = {
      password.enabled = cfg.passwordAuthEnabled;
    }
    // lib.optionalAttrs cfg.oidc.enabled {
      oidc = {
        enabled = true;
        issuerUrl = cfg.oidc.issuerUrl;
        scopes = cfg.oidc.scopes;
        userIdentifier = cfg.oidc.userIdentifier;
      }
      // lib.optionalAttrs (cfg.oidc.clientId != null) {
        clientId = cfg.oidc.clientId;
      };
    };

    server = {
      listen = "0.0.0.0";
      port = 8080;
      sources = quantumSources;
    };
  };

  generatedConfig = (pkgs.formats.yaml { }).generate "quantum-config.yaml" quantumConfig;

  sshfsFileSystems = lib.listToAttrs (
    map (host: {
      name = mountPathFor host;
      value = {
        device = "${host.user}@${host.host}:${host.remotePath}";
        fsType = "fuse.sshfs";
        options = [
          "_netdev"
          "x-systemd.automount"
          "noauto"
          "reconnect"
          "allow_other"
          "default_permissions"
          "ServerAliveInterval=15"
          "ServerAliveCountMax=3"
          "uid=${toString cfg.runtimeUid}"
          "gid=${toString cfg.runtimeGid}"
          "IdentityFile=${cfg.sftp.identityFile}"
          "StrictHostKeyChecking=yes"
          "UserKnownHostsFile=${cfg.sftp.knownHostsFile}"
        ]
        ++ lib.optionals host.readOnly [ "ro" ];
      };
    }) cfg.sftp.hosts
  );

  hasOidcSecrets = cfg.oidc.enabled;
  needsAuthTemplate =
    cfg.passwordAuthEnabled && cfg.environmentFile == null && cfg.adminPassword == null;
in
{
  options.services.admin.quantum = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable admin-owned Quantum service wiring.";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = ociImages.quantum;
      description = "Pinned Quantum container image.";
    };

    runtimeUid = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 1000;
      description = "Host UID that should own/write Quantum data files.";
    };

    runtimeGid = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 1000;
      description = "Host GID that should own/write Quantum data files.";
    };

    adminPassword = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Initial Quantum admin password passed as FILEBROWSER_ADMIN_PASSWORD.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional env-file for Quantum runtime variables (for example FILEBROWSER_ADMIN_PASSWORD).";
    };

    passwordAuthEnabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Keep local/password auth enabled (set false after manual OIDC smoke validation).";
    };

    managedSourceEnabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Expose Quantum managed data path (`/srv`) as the built-in Local Files source.";
    };

    oidc = {
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Quantum OIDC auth method wiring.";
      };

      issuerUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "OIDC issuer URL for Quantum authentication.";
      };

      clientId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional Quantum OIDC client ID (can also be provided by env file).";
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional env-file for OIDC variables (for example FILEBROWSER_OIDC_CLIENT_ID/SECRET).";
      };

      scopes = lib.mkOption {
        type = lib.types.str;
        default = "openid email profile";
        description = "OIDC scopes string for Quantum.";
      };

      userIdentifier = lib.mkOption {
        type = lib.types.enum [
          "preferred_username"
          "email"
          "username"
          "phone"
        ];
        default = "preferred_username";
        description = "OIDC claim Quantum uses as the user identifier.";
      };
    };

    sftp = {
      identityFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "SSH private key path for Quantum host SFTP mounts.";
      };

      knownHostsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Known hosts file path for Quantum host SFTP mounts.";
      };

      hosts = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule (
            { ... }:
            {
              options = {
                name = lib.mkOption {
                  type = lib.types.str;
                  description = "Host source label and mount directory name.";
                };

                host = lib.mkOption {
                  type = lib.types.str;
                  description = "SFTP endpoint host (typically Tailscale DNS name).";
                };

                user = lib.mkOption {
                  type = lib.types.str;
                  default = "dev";
                  description = "Remote SSH username used for SFTP mount.";
                };

                remotePath = lib.mkOption {
                  type = lib.types.str;
                  default = "/srv/data";
                  description = "Remote host path exposed as this Quantum source.";
                };

                readOnly = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "Mount source read-only by default.";
                };
              };
            }
          )
        );
        default = [ ];
        description = "SFTP host list exposed as Quantum sources via SSHFS mounts.";
      };
    };

    localSources = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule (
          { ... }:
          {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                description = "Quantum source display name for local bind-mounted paths.";
              };

              path = lib.mkOption {
                type = lib.types.str;
                description = "Container-visible path for local source (for example /srv/data).";
              };
            };
          }
        )
      );
      default = [ ];
      description = "Additional local filesystem sources exposed to Quantum.";
    };

    secretFiles.host = secretHelpers.mkSecretFileOption "quantum-host-secrets";
    secretFiles.oidc = secretHelpers.mkSecretFileOption "quantum-oidc-secrets";
  };

  config = lib.mkIf (appCfg.enable && cfg.enable) {
    assertions = [
      (secretHelpers.mkRequiredSecretAssertion {
        enable = cfg.enable;
        file = cfg.secretFiles.host;
        feature = "services.admin.quantum";
        label = "secretFiles.host";
      })
      {
        assertion = !cfg.oidc.enabled || cfg.secretFiles.oidc != null;
        message = "services.admin.quantum.oidc is enabled but secretFiles.oidc is not set.";
      }
      {
        assertion = !cfg.passwordAuthEnabled || (cfg.adminPassword != null || cfg.environmentFile != null);
        message = "When services.admin.quantum.passwordAuthEnabled=true, set services.admin.quantum.adminPassword or services.admin.quantum.environmentFile.";
      }
      {
        assertion = !cfg.oidc.enabled || cfg.oidc.issuerUrl != null;
        message = "services.admin.quantum.oidc.issuerUrl must be set when services.admin.quantum.oidc.enabled=true.";
      }
      {
        assertion = !cfg.oidc.enabled || (cfg.oidc.clientId != null || cfg.oidc.environmentFile != null);
        message = "When Quantum OIDC is enabled, set services.admin.quantum.oidc.clientId or services.admin.quantum.oidc.environmentFile.";
      }
      {
        assertion =
          cfg.sftp.hosts == [ ] || (cfg.sftp.identityFile != null && cfg.sftp.knownHostsFile != null);
        message = "When services.admin.quantum.sftp.hosts is non-empty, set services.admin.quantum.sftp.identityFile and knownHostsFile.";
      }
    ];

    # Auth env file - always owned by quantum module when needed
    sops.templates."quantum-auth.env" = lib.mkIf needsAuthTemplate {
      owner = "root";
      group = "root";
      mode = "0400";
      content = ''
        FILEBROWSER_ADMIN_PASSWORD=${config.sops.placeholder.quantum_admin_password}
      '';
    };

    # OIDC env file - owned by quantum module when OIDC is enabled
    sops.templates."quantum-oidc.env" = lib.mkIf hasOidcSecrets {
      owner = "root";
      group = "root";
      mode = "0400";
      content = ''
        FILEBROWSER_OIDC_CLIENT_ID=${cfg.oidc.clientId}
        FILEBROWSER_OIDC_CLIENT_SECRET=${config.sops.placeholder.quantum_oidc_client_secret}
      '';
    };

    # Password auth secrets from host secrets file
    # OIDC secrets from oidc secrets file when OIDC is enabled
    sops.secrets = lib.mkMerge [
      (lib.mkIf needsAuthTemplate (
        secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
          quantum_admin_password = {
            key = "quantum/admin_password";
            path = "/run/secrets/quantum.admin_password";
            owner = "root";
            group = "root";
          };
        }
      ))
      (lib.mkIf hasOidcSecrets (
        secretHelpers.mkSecretsFromMap cfg.secretFiles.oidc {
          quantum_oidc_client_secret = {
            key = "quantum/client_secret";
            path = "/run/secrets/quantum.oidc_client_secret";
            owner = "root";
            group = "root";
          };
        }
      ))
    ];

    virtualisation.podman.enable = true;

    environment.systemPackages = [ pkgs.sshfs ];

    systemd.tmpfiles.rules = [
      "d ${appCfg.dataRoot}/quantum 0750 ${toString cfg.runtimeUid} ${toString cfg.runtimeGid} - -"
      "d ${appCfg.dataRoot}/quantum/files 0750 ${toString cfg.runtimeUid} ${toString cfg.runtimeGid} - -"
      "d ${mountRoot} 0755 root root - -"
      "z ${mountRoot} 0755 root root - -"
    ]
    ++ lib.optionals (cfg.localSources != [ ]) [
      "d ${localSourceMaskDir} 0555 root root - -"
    ]
    ++ lib.concatMap (host: [
      "d ${mountPathFor host} 0755 root root - -"
      "z ${mountPathFor host} 0755 root root - -"
    ]) cfg.sftp.hosts;

    fileSystems = sshfsFileSystems;

    virtualisation.oci-containers.containers.quantum = {
      autoStart = true;
      image = cfg.image;
      ports = [
        "${listenAddress}:${toString listenPort}:8080"
      ];
      environment = {
        FILEBROWSER_CONFIG = "/etc/quantum/config.yaml";
      }
      // lib.optionalAttrs (cfg.adminPassword != null) {
        FILEBROWSER_ADMIN_PASSWORD = cfg.adminPassword;
      };
      environmentFiles =
        lib.optionals (cfg.environmentFile != null) [ cfg.environmentFile ]
        ++ lib.optionals (cfg.oidc.environmentFile != null) [ cfg.oidc.environmentFile ];
      volumes = [
        "${appCfg.dataRoot}/quantum:/home/filebrowser/data"
        "${appCfg.dataRoot}/quantum/files:/srv"
        "${mountRoot}:/mnt/hosts:ro"
        "${generatedConfig}:/etc/quantum/config.yaml:ro"
      ]
      ++ lib.optionals (cfg.localSources != [ ]) [
        "${appCfg.dataRoot}:${localSourceBindPath}:ro"
        "${localSourceMaskDir}:${localSourceMaskPath}:ro"
      ];
    };

    systemd.services.quantum-permissions-reconcile = {
      description = "Reconcile Quantum data directory ownership and permissions";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-tmpfiles-setup.service" ];
      before = [ "podman-quantum.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "quantum-permissions-reconcile" ''
          set -euo pipefail
          install -d -m 0750 -o ${toString cfg.runtimeUid} -g ${toString cfg.runtimeGid} "${appCfg.dataRoot}/quantum"
          install -d -m 0750 -o ${toString cfg.runtimeUid} -g ${toString cfg.runtimeGid} "${appCfg.dataRoot}/quantum/files"
          chown ${toString cfg.runtimeUid}:${toString cfg.runtimeGid} "${appCfg.dataRoot}/quantum"
          if [ -d "${appCfg.dataRoot}/quantum" ]; then
            find "${appCfg.dataRoot}/quantum" -mindepth 1 -maxdepth 1 ! -name mnt -exec chown -R ${toString cfg.runtimeUid}:${toString cfg.runtimeGid} {} +
          fi
        '';
      };
    };

    systemd.services."podman-quantum" = {
      wants = [
        "network-online.target"
        "systemd-tmpfiles-setup.service"
        "quantum-permissions-reconcile.service"
      ];
      after = [
        "network-online.target"
        "systemd-tmpfiles-setup.service"
        "quantum-permissions-reconcile.service"
      ];
      unitConfig.RequiresMountsFor = [
        "${appCfg.dataRoot}/quantum"
        "${appCfg.dataRoot}/quantum/files"
        mountRoot
      ];
    };

  };
}
