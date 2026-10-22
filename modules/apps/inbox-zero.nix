# Gmail assistant: digest-pinned container on its own bridge, native PostgreSQL consumer,
# two maintenance timers. Selection is enablement.
_: {
  flake.modules.nixos.inbox-zero =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.inbox-zero;
      globals = import ../../policy/globals.nix;
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };
      route = config.repo.web.catalog.inbox-zero or null;

      # Upstream's start script listens on 3000 inside the container. The host
      # side is the route's loopback port, so the edge reaches it as `direct`.
      containerPort = 3000;
      serviceHost = globals.serviceNetwork.hostName;
      serviceAddress = globals.serviceNetwork.address;
      networkName = "inbox-zero-net";
      environmentFile = config.sops.templates."inbox-zero.environment".path;
      localPostgres = config.services.postgres.localEndpoint;
      bifrost = config.services.bifrost.endpoint.containerBaseUrl or "";
      model = globals.bifrost.aliases.text;

      # Checked at unit start on the rendered file: upstream catches startup errors and
      # keeps running, so an empty credential would otherwise look healthy.
      requiredEnv = [
        "DATABASE_URL"
        "AUTH_SECRET"
        "EMAIL_ENCRYPT_SECRET"
        "EMAIL_ENCRYPT_SALT"
        "GOOGLE_CLIENT_ID"
        "GOOGLE_CLIENT_SECRET"
        "GOOGLE_PUBSUB_TOPIC_NAME"
        "GOOGLE_PUBSUB_VERIFICATION_TOKEN"
        "CRON_SECRET"
        "INTERNAL_API_KEY"
        "AUTH_ALLOWED_EMAILS"
      ];

      validateEnvironment = pkgs.writeShellScript "inbox-zero-validate-environment" ''
        set -eu
        for key in ${lib.concatStringsSep " " requiredEnv}; do
          value=$(${pkgs.gnused}/bin/sed -n "s/^$key=//p" "$1")
          if [ -z "$value" ]; then
            echo "inbox-zero: $key is empty in the rendered environment" >&2
            exit 1
          fi
        done
      '';

      # The cron secret rides stdin (curl --config -) so it never reaches an argument list.
      cronCall =
        name: path:
        pkgs.writeShellScript "inbox-zero-${name}" ''
          set -eu
          printf 'header = "Authorization: Bearer %s"\n' "$CRON_SECRET" \
            | ${pkgs.curl}/bin/curl --fail --silent --show-error --max-time 300 \
                --retry 12 --retry-connrefused --retry-delay 5 \
                --output /dev/null --config - \
                "http://127.0.0.1:${toString route.upstreamPort}${path}"
        '';
    in
    {
      imports = [ ../database/postgres/_consumer.nix ];

      options.services.inbox-zero = {
        enable = lib.mkEnableOption "Inbox Zero Gmail assistant";

        secretFiles.host = secretHelpers.mkSecretFileOption "inbox-zero-host-secrets";

        networkSubnet = lib.mkOption {
          type = lib.types.str;
          default = "10.89.43.0/24";
          description = ''
            Subnet for the app-owned Podman bridge. Pinned because the PostgreSQL
            registration allows exactly this range to authenticate as the Inbox Zero
            role, so the scope is the application's and not the shared container range.
          '';
        };
      };

      config = lib.mkMerge [
        # Selection is enablement.
        { services.inbox-zero.enable = true; }

        (lib.mkIf cfg.enable {
          assertions = [
            {
              assertion = route != null;
              message = "services.inbox-zero: canonical web-policy route 'repo.web.catalog.inbox-zero' is missing; declare the inbox-zero route under its host in policy/web-services.nix.";
            }
            {
              assertion = localPostgres != null;
              message = "services.inbox-zero: this host runs no PostgreSQL cluster; select the postgres aspect and declare services.postgres.instances.<name>.";
            }
            {
              assertion = bifrost != "";
              message = "services.inbox-zero: services.bifrost.endpoint is unavailable; select the bifrost aspect on this host.";
            }
            (secretHelpers.mkRequiredSecretAssertion {
              inherit (cfg) enable;
              file = cfg.secretFiles.host;
              feature = "services.inbox-zero";
              label = "secretFiles.host";
            })
          ];

          # The database role and its scram password come from the same key the
          # provider reads to provision the role.
          services.postgres.consumers.inbox-zero = {
            database = "inbox_zero";
            role = "inbox_zero";
            auth = "scram";
            password = {
              file = cfg.secretFiles.host;
              key = "inbox-zero/database_password";
            };
            allowedCIDRs = [ cfg.networkSubnet ];
            # uuid-ossp is deliberately absent: its migration creates and drops it, and only the
            # creating role may drop it. Installed by the superuser it froze every later migration.
            setupSQL = ''
              CREATE EXTENSION IF NOT EXISTS btree_gist;
            '';
          };

          sops.secrets = secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
            inbox_zero_database_password = {
              key = "inbox-zero/database_password";
              path = "/run/secrets/inbox-zero.database_password";
            };
            inbox_zero_auth_secret = {
              key = "inbox-zero/auth_secret";
              path = "/run/secrets/inbox-zero.auth_secret";
            };
            inbox_zero_email_encrypt_secret = {
              key = "inbox-zero/email_encrypt_secret";
              path = "/run/secrets/inbox-zero.email_encrypt_secret";
            };
            inbox_zero_email_encrypt_salt = {
              key = "inbox-zero/email_encrypt_salt";
              path = "/run/secrets/inbox-zero.email_encrypt_salt";
            };
            inbox_zero_google_client_id = {
              key = "inbox-zero/google_client_id";
              path = "/run/secrets/inbox-zero.google_client_id";
            };
            inbox_zero_google_client_secret = {
              key = "inbox-zero/google_client_secret";
              path = "/run/secrets/inbox-zero.google_client_secret";
            };
            inbox_zero_pubsub_topic = {
              key = "inbox-zero/google_pubsub_topic_name";
              path = "/run/secrets/inbox-zero.pubsub_topic";
            };
            inbox_zero_pubsub_token = {
              key = "inbox-zero/pubsub_verification_token";
              path = "/run/secrets/inbox-zero.pubsub_verification_token";
            };
            inbox_zero_cron_secret = {
              key = "inbox-zero/cron_secret";
              path = "/run/secrets/inbox-zero.cron_secret";
            };
            inbox_zero_internal_api_key = {
              key = "inbox-zero/internal_api_key";
              path = "/run/secrets/inbox-zero.internal_api_key";
            };
            inbox_zero_allowed_emails = {
              key = "inbox-zero/auth_allowed_emails";
              path = "/run/secrets/inbox-zero.allowed_emails";
            };
          };

          sops.templates."inbox-zero.environment" = {
            owner = "root";
            group = "root";
            mode = "0400";
            content = ''
              DATABASE_URL=postgresql://inbox_zero:${config.sops.placeholder.inbox_zero_database_password}@${serviceHost}:${toString localPostgres.port}/inbox_zero
              AUTH_SECRET=${config.sops.placeholder.inbox_zero_auth_secret}
              EMAIL_ENCRYPT_SECRET=${config.sops.placeholder.inbox_zero_email_encrypt_secret}
              EMAIL_ENCRYPT_SALT=${config.sops.placeholder.inbox_zero_email_encrypt_salt}
              GOOGLE_CLIENT_ID=${config.sops.placeholder.inbox_zero_google_client_id}
              GOOGLE_CLIENT_SECRET=${config.sops.placeholder.inbox_zero_google_client_secret}
              GOOGLE_PUBSUB_TOPIC_NAME=${config.sops.placeholder.inbox_zero_pubsub_topic}
              GOOGLE_PUBSUB_VERIFICATION_TOKEN=${config.sops.placeholder.inbox_zero_pubsub_token}
              CRON_SECRET=${config.sops.placeholder.inbox_zero_cron_secret}
              INTERNAL_API_KEY=${config.sops.placeholder.inbox_zero_internal_api_key}
              AUTH_ALLOWED_EMAILS=${config.sops.placeholder.inbox_zero_allowed_emails}
            '';
          };

          virtualisation = {
            podman.enable = true;

            oci-containers.containers.inbox-zero = {
              autoStart = true;
              image = config.repo.ociImages.inboxZero;
              extraOptions = [
                "--network=${networkName}"
                # The database is the fleet's service address; a bridged container
                # cannot dial the host's loopback.
                "--add-host=${serviceHost}:${serviceAddress}"
              ];
              # Loopback publish: the socket stays edge-local, so the route is `direct`.
              ports = [ "127.0.0.1:${toString route.upstreamPort}:${toString containerPort}" ];
              environment = {
                NODE_ENV = "production";
                NEXT_PUBLIC_BASE_URL = route.publicUrl;
                # Upstream recommends this for personal self-hosting.
                NEXT_PUBLIC_BYPASS_PREMIUM_CHECKS = "true";
                QUEUE_BACKEND = "internal";
                # The web process calls its own internal handlers inside its namespace.
                INTERNAL_API_URL = "http://127.0.0.1:${toString containerPort}";
                DEFAULT_LLM_PROVIDER = "openai-compatible";
                DEFAULT_LLM_MODEL = model;
                OPENAI_COMPATIBLE_MODEL = model;
                OPENAI_COMPATIBLE_BASE_URL = bifrost;
              };
              environmentFiles = [ environmentFile ];
            };
          };

          systemd = {
            services = {
              "podman-network-${networkName}" = {
                description = "Create Podman network ${networkName}";
                before = [ "podman-inbox-zero.service" ];
                wantedBy = [ "podman-inbox-zero.service" ];
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  ExecStart = "${pkgs.runtimeShell} -c '${pkgs.podman}/bin/podman network exists ${networkName} || ${pkgs.podman}/bin/podman network create --subnet=${cfg.networkSubnet} ${networkName}'";
                  ExecStop = "${pkgs.runtimeShell} -c '${pkgs.podman}/bin/podman network rm -f ${networkName} || true'";
                };
              };

              inbox-zero-environment = {
                description = "Check the rendered Inbox Zero environment";
                before = [ "podman-inbox-zero.service" ];
                requiredBy = [ "podman-inbox-zero.service" ];
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  ExecStart = "${validateEnvironment} ${environmentFile}";
                };
              };

              "podman-inbox-zero" = {
                wants = [ "network-online.target" ];
                after = [
                  "network-online.target"
                  "postgresql-provision.service"
                  "podman-network-${networkName}.service"
                ];
                requires = [
                  "postgresql-provision.service"
                  "podman-network-${networkName}.service"
                ];
                serviceConfig.RestartSec = "15s";
              };

              inbox-zero-watch-renewal = {
                description = "Renew Inbox Zero Gmail watches";
                wants = [ "podman-inbox-zero.service" ];
                after = [ "podman-inbox-zero.service" ];
                serviceConfig = {
                  Type = "oneshot";
                  EnvironmentFile = environmentFile;
                  ExecStart = cronCall "watch-renewal" "/api/watch/all";
                };
              };

              inbox-zero-scheduled-actions = {
                description = "Run Inbox Zero scheduled actions";
                wants = [ "podman-inbox-zero.service" ];
                after = [ "podman-inbox-zero.service" ];
                serviceConfig = {
                  Type = "oneshot";
                  EnvironmentFile = environmentFile;
                  ExecStart = cronCall "scheduled-actions" "/api/cron/scheduled-actions";
                };
              };
            };

            timers = {
              inbox-zero-watch-renewal = {
                description = "Renew Inbox Zero Gmail watches every six hours";
                wantedBy = [ "timers.target" ];
                timerConfig = {
                  OnActiveSec = "5min";
                  OnUnitActiveSec = "6h";
                  Persistent = true;
                };
              };

              inbox-zero-scheduled-actions = {
                description = "Run Inbox Zero scheduled actions every minute";
                wantedBy = [ "timers.target" ];
                timerConfig = {
                  OnActiveSec = "1min";
                  OnUnitActiveSec = "1min";
                  Persistent = false;
                };
              };
            };
          };

          # Notification participation is owned here: a failed container or
          # maintenance call is an operator-visible event.
          services.notify.events = {
            "podman-inbox-zero".failure = { };
            "inbox-zero-watch-renewal".failure = { };
            "inbox-zero-scheduled-actions".failure = { };
          };
        })
      ];
    };
}
