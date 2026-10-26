# Authentik runtime: server, worker and database. Registrations come from ./blueprints.nix.
{ inputs, ... }:
{
  flake.modules.nixos.authentik-identity =
    {
      lib,
      config,
      ...
    }:
    let
      secretHelpers = import ../../../lib/secrets.nix { inherit lib; };
      globals = import ../../../policy/globals.nix;
      identityPolicy = import ../../../policy/identity.nix;
      secretSources = import ../_secret-sources.nix;
      credentials = import ./_credentials.nix { inherit lib; };
      enabledClients = lib.filterAttrs (_name: client: client.enable or true) identityPolicy.clients;

      route = config.repo.web.catalog.${identityPolicy.providers.authentik.route};
      inherit (route) publicUrl;
      localEndpoint = config.services.postgres.localEndpoint;

      runtimeSecret = secretSources.authentik;
      clientSecretName = credentials.secretName;
      clientSecretEnv = credentials.envVar;
    in
    {
      imports = [
        inputs.authentik-nix.nixosModules.default
        ../../database/postgres/_consumer.nix
        ../_oidc.nix
      ];

      config = {
        assertions = [
          {
            assertion =
              identityPolicy.provider != "authentik" || config.services.identity.oidc.providerUrl == publicUrl;
            message = "authentik-identity: the provider URL and the active application identity must agree while Authentik serves application SSO.";
          }
        ];

        services.postgres.consumers.authentik = {
          database = "authentik";
          role = "authentik";
          auth = "scram";
          password = {
            file = runtimeSecret;
            key = "authentik/postgres_password";
          };
          allowedCIDRs = [ "127.0.0.1/32" ];
        };

        sops.secrets =
          secretHelpers.mkSecretsFromMap runtimeSecret {
            authentik_secret_key = {
              key = "authentik/secret_key";
              path = "/run/secrets/authentik.secret_key";
            };
            authentik_postgres_password = {
              key = "authentik/postgres_password";
              path = "/run/secrets/authentik.postgres_password";
            };
            authentik_bootstrap_password = {
              key = "authentik/bootstrap_password";
              path = "/run/secrets/authentik.bootstrap_password";
            };
            authentik_bootstrap_token = {
              key = "authentik/bootstrap_token";
              path = "/run/secrets/authentik.bootstrap_token";
            };
            authentik_smtp_username = {
              key = "authentik/smtp_username";
              path = "/run/secrets/authentik.smtp_username";
            };
            authentik_smtp_password = {
              key = "authentik/smtp_password";
              path = "/run/secrets/authentik.smtp_password";
            };
          }
          # Reads each application's existing client secret file rather than duplicating it.
          // lib.mapAttrs' (
            name: _:
            lib.nameValuePair (clientSecretName name) {
              sopsFile = secretSources.clients.${name};
              key = "${name}/client_secret";
              path = "/run/secrets/authentik.client.${name}";
            }
          ) enabledClients;

        sops.templates."authentik.env" = {
          content = ''
            AUTHENTIK_SECRET_KEY=${config.sops.placeholder.authentik_secret_key}
            AUTHENTIK_POSTGRESQL__PASSWORD=${config.sops.placeholder.authentik_postgres_password}
            AUTHENTIK_BOOTSTRAP_PASSWORD=${config.sops.placeholder.authentik_bootstrap_password}
            AUTHENTIK_BOOTSTRAP_TOKEN=${config.sops.placeholder.authentik_bootstrap_token}
            AUTHENTIK_EMAIL__HOST=smtp.resend.com
            AUTHENTIK_EMAIL__PORT=587
            AUTHENTIK_EMAIL__FROM=auth@${globals.domain}
            AUTHENTIK_EMAIL__USERNAME=${config.sops.placeholder.authentik_smtp_username}
            AUTHENTIK_EMAIL__PASSWORD=${config.sops.placeholder.authentik_smtp_password}
            # Resend's submission port offers STARTTLS; USE_TLS and USE_SSL are exclusive.
            AUTHENTIK_EMAIL__USE_TLS=true
          ''
          + lib.concatStrings (
            lib.mapAttrsToList (
              name: _: "${clientSecretEnv name}=${config.sops.placeholder.${clientSecretName name}}\n"
            ) enabledClients
          );
          restartUnits = [
            "authentik.service"
            "authentik-worker.service"
            "authentik-migrate.service"
          ];
        };

        services.authentik = {
          enable = true;
          createDatabase = false;
          environmentFile = config.sops.templates."authentik.env".path;

          settings = {
            listen.http = [ "127.0.0.1:${toString route.upstreamPort}" ];
            # The default wildcard :9443 collides with tailnet-address fronts bound on the same port.
            listen.https = [ "127.0.0.1:9443" ];
            # Seed only: copied into the database once.
            web.base_url = publicUrl;
            postgresql = {
              host = "127.0.0.1";
              port = localEndpoint.port;
              name = "authentik";
              user = "authentik";
            };
          };
        };

        services.notify.events."authentik".failure = { };
        services.notify.events."authentik-worker".failure = { };

        # NixOS disables the manager-wide start rate limit; without these, a config error
        # restarts every second and OnFailure never fires.
        systemd.services = {
          authentik.startLimitIntervalSec = 3600;
          authentik.startLimitBurst = 5;
          authentik-worker.startLimitIntervalSec = 3600;
          authentik-worker.startLimitBurst = 5;
        };

        services.state-backups.services.authentik = {
          enable = true;
          mode = "live";
          paths = [ "/var/lib/authentik" ];
        };
      };
    };
}
