# Metrics, logs and traces store with its Grafana front end. Ports close over their
# web-policy declarations; state lives on the root filesystem, bounded by retention.
{ inputs, ... }:
{
  flake.modules.nixos.victoria =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.victoria;
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };

      catalog = config.repo.web.catalog or { };
      route =
        catalog.grafana
          or (throw "victoria: required canonical web-policy route 'repo.web.catalog.\"grafana\"' is missing for host '${
            config.networking.hostName or "?"
          }'; select the host's web policy with a grafana route");

      metricsPort = catalog.victoriametrics.endpoint.port;
      logsPort = catalog.victorialogs.endpoint.port;
      tracesPort = catalog.victoriatraces.endpoint.port;

      listenAddress = port: "${cfg.listenAddress}:${toString port}";

      # Per-client OIDC endpoints come from the intrinsic contract and resolve once identity enables the client.
      oidcClient = config.services.identity.oidc.clients.grafana or null;

      # Datasource uids are declared once: dashboards address them, and an unresolvable one fails provisioning.
      prometheusUid = "victoriametrics";
      metricsqlUid = "victoriametrics-metricsql";
      logsUid = "victorialogs";
      tracesUid = "victoriatraces";

      # Boards are rewritten to address this store's datasources: uid and type bound, template
      # variables selected, grafana.com placeholders substituted, import metadata dropped.
      dashboardSources = [
        {
          slug = "node-exporter-full";
          folder = "host";
          datasourceUid = prometheusUid;
          datasourceType = "prometheus";
          url = "https://grafana.com/api/dashboards/1860/revisions/45/download";
          hash = "sha256-GExrdAnzBtp1Ul13cvcZRbEM6iOtFrXXjEaY6g6lGYY=";
        }
        {
          slug = "victoriametrics-single-node";
          folder = "telemetry";
          datasourceUid = prometheusUid;
          datasourceType = "prometheus";
          url = "https://raw.githubusercontent.com/VictoriaMetrics/VictoriaMetrics/v1.152.0/dashboards/victoriametrics.json";
          hash = "sha256-frWcHmiH/SKu1ZWbTdMlmHKcQgrJDG3ZUIiK4nt1nYA=";
        }
        {
          slug = "victorialogs-single-node";
          folder = "telemetry";
          datasourceUid = logsUid;
          datasourceType = "victoriametrics-logs-datasource";
          url = "https://raw.githubusercontent.com/VictoriaMetrics/VictoriaLogs/v1.52.0/dashboards/victorialogs.json";
          hash = "sha256-B6F+zkNidnK9yDNablGogcEa5Y8YT1FiMJTiBNhL5Wk=";
        }
        {
          slug = "victoriatraces-single-node";
          folder = "telemetry";
          datasourceUid = tracesUid;
          datasourceType = "jaeger";
          url = "https://raw.githubusercontent.com/VictoriaMetrics/VictoriaTraces/v0.11.1/dashboards/victoriatraces.json";
          hash = "sha256-UHDflmMyp0LFbM9SMgQevmDaedze0EH2soO7O6IZW2M=";
        }
        {
          slug = "niks3-cache";
          folder = "fleet";
          datasourceUid = prometheusUid;
          datasourceType = "prometheus";
          file = inputs.niks3.dashboards.niks3;
          # Labelled by the canonical `host`, not `instance`, so the variable and every query move with it.
          # The `Last GC` mask divides: a 1.15.0 server reports 0 before any GC, and subtracting renders the epoch.
          extraJq = ''
            | (.templating.list[]? | select(.name == "instance")) |= (.name = "host" | .label = "host")
            | walk(if type == "string" then gsub("\\binstance\\b"; "host") else . end)
            | walk(
                if type == "string"
                   and . == "time() - (niks3_gc_last_run_timestamp_seconds{host=~\"$host\"} > 0)"
                then
                  "(time() - niks3_gc_last_run_timestamp_seconds{host=~\"$host\"})"
                  + " / (niks3_gc_last_run_timestamp_seconds{host=~\"$host\"} > 0)"
                else . end)
          '';
        }
        {
          slug = "tailscale-machine";
          folder = "fleet";
          datasourceUid = prometheusUid;
          datasourceType = "prometheus";
          url = "https://grafana.com/api/dashboards/24178/revisions/7/download";
          hash = "sha256-gJ3x0LeXxPJ1dhUf7MPNu4E4A8h2Bp8WUAQBaT0FxSg=";
          # Rewritten to this fleet's `host` label; the tailscale-mixin dimensions do not exist here.
          extraJq = ''
            | del(.templating.list[]? | select(.name == "cluster"))
            | walk(if type == "string" then gsub("cluster=\"\\$cluster\"\\s*,?\\s*"; "") | gsub("tailscale_machine"; "host") else . end)
            | walk(if type == "object" then with_entries(.key |= gsub("tailscale_machine"; "host")) else . end)
          '';
        }
      ];

      # A folder is the directory a board is staged into.
      dashboardFolders = [
        {
          title = "Fleet";
          dir = "fleet";
        }
        {
          title = "Host";
          dir = "host";
        }
        {
          title = "Telemetry";
          dir = "telemetry";
        }
      ];

      # Authored boards are copied verbatim: they already address this store's datasource.
      authoredDashboards = [
        {
          slug = "fleet-overview";
          folder = "fleet";
          file = ./dashboards/fleet-overview.json;
        }
        {
          slug = "pipeline-health";
          folder = "telemetry";
          file = ./dashboards/pipeline-health.json;
        }
      ];

      dashboards = pkgs.runCommand "victoria-grafana-dashboards" { nativeBuildInputs = [ pkgs.jq ]; } (
        lib.concatStrings (
          [ "mkdir -p $out\n" ]
          ++ map (folder: "mkdir -p $out/${folder.dir}\n") dashboardFolders
          ++ map (dashboard: ''
            jq '
              (.. | objects | .datasource? | select(type == "object") | .uid)
                |= "${dashboard.datasourceUid}"
              | (.. | objects | .datasource? | select(type == "object") | .type)
                |= "${dashboard.datasourceType}"
              | (.templating.list[]? | select(.type == "datasource") | .current)
                = { text: "${dashboard.datasourceUid}", value: "${dashboard.datasourceUid}" }
              | (.templating.list[]? | select(.type == "datasource") | .query)
                = "${dashboard.datasourceType}"
              | walk(
                  if type == "string" then
                    if test("^\\$\\{?DS_PROMETHEUS\\}?$") then "${prometheusUid}"
                    elif test("^\\$\\{?DS_VICTORIALOGS\\}?$") then "${logsUid}"
                    elif test("^\\$\\{?DS_VICTORIATRACES\\}?$") then "${tracesUid}"
                    elif test("^-- Grafana --$") then "${dashboard.datasourceUid}"
                    else . end
                  else . end)
              | del(.__inputs, .__requires, .__elements)
              | .id = null
              | .uid = "${dashboard.slug}"${dashboard.extraJq or ""}' \
              ${
                if dashboard ? file then
                  dashboard.file
                else
                  pkgs.fetchurl {
                    name = "${dashboard.slug}.json";
                    inherit (dashboard) url hash;
                  }
              } > $out/${dashboard.folder}/${dashboard.slug}.json
          '') dashboardSources
          ++ map (board: "cp ${board.file} $out/${board.folder}/${board.slug}.json\n") authoredDashboards
        )
      );
    in
    {
      imports = [
        ../identity/_oidc.nix
      ];

      options.services.victoria = {
        listenAddress = lib.mkOption {
          type = lib.types.str;
          default = "0.0.0.0";
          description = ''
            Interface the store and Grafana bind. The fleet trusts the tailnet
            interface, so the wildcard address keeps the ingest endpoints
            reachable by tailnet peers and the firewall keeps them shut
            everywhere else.
          '';
        };

        scrapeInterval = lib.mkOption {
          type = lib.types.str;
          default = "30s";
          description = "Scrape interval for the store's own self-scrape job.";
        };

        metrics.retentionPeriod = lib.mkOption {
          type = lib.types.str;
          default = "12";
          description = "VictoriaMetrics retention, in its own units (`12` = 12 months).";
        };

        logs.retentionPeriod = lib.mkOption {
          type = lib.types.str;
          default = "30d";
          description = "VictoriaLogs retention period.";
        };

        traces.retentionPeriod = lib.mkOption {
          type = lib.types.str;
          default = "30d";
          description = "VictoriaTraces retention period.";
        };

        oidc.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Authenticate Grafana against the fleet identity provider instead of
            serving anonymous viewers. Requires both the canonical `grafana`
            oauth2 client in the identity policy and this host's OIDC secret
            file; the route stays behind Cloudflare Access either way.
          '';
        };

        secretFiles.oidc = secretHelpers.mkSecretFileOption "victoria-grafana-oidc-secrets";

        # The local administrator's password, seeded at startup. OIDC hides the login form,
        # so re-enabling it with this credential is the way back in when the provider is
        # unreachable. Service-scoped and host-agnostic, so the module defaults it; a host
        # overrides only to bind a different file.
        secretFiles.admin = secretHelpers.mkSecretFileOptionWithDefault "victoria-grafana-admin-credential" ../../secrets/services/grafana.yaml;
      };

      config = {

        assertions = [
          {
            assertion = !cfg.oidc.enable || cfg.secretFiles.oidc != null;
            message = "services.victoria.secretFiles.oidc must be set when services.victoria.oidc.enable=true.";
          }
          {
            assertion = !cfg.oidc.enable || oidcClient != null;
            message = "services.victoria.oidc.enable requires the canonical 'grafana' oauth2 client in policy/identity.nix.";
          }
        ];

        sops.secrets = lib.mkMerge [
          (lib.mkIf (cfg.oidc.enable && cfg.secretFiles.oidc != null) {
            victoria_grafana_client_secret = {
              sopsFile = cfg.secretFiles.oidc;
              key = "grafana/client_secret";
              owner = "grafana";
              group = "grafana";
              mode = "0400";
            };
            victoria_grafana_secret_key = {
              sopsFile = cfg.secretFiles.oidc;
              key = "grafana/secret_key";
              owner = "grafana";
              group = "grafana";
              mode = "0400";
            };
          })
          (lib.optionalAttrs (cfg.secretFiles.admin != null) {
            victoria_grafana_admin_password = {
              sopsFile = cfg.secretFiles.admin;
              key = "grafana/admin_password";
              owner = "grafana";
              group = "grafana";
              mode = "0400";
            };
          })
        ];

        services.victoriametrics = {
          enable = true;
          listenAddress = listenAddress metricsPort;
          retentionPeriod = cfg.metrics.retentionPeriod;

          # The store scrapes its own endpoints; producers push theirs through the telemetry collector.
          prometheusConfig = {
            global.scrape_interval = cfg.scrapeInterval;
            scrape_configs = [
              {
                job_name = "victoria";
                static_configs = [
                  {
                    targets = [
                      "127.0.0.1:${toString metricsPort}"
                      "127.0.0.1:${toString logsPort}"
                      "127.0.0.1:${toString tracesPort}"
                    ];
                  }
                ];
              }
            ];
          };
        };

        services.victorialogs = {
          enable = true;
          listenAddress = listenAddress logsPort;
          # VictoriaLogs' 7-day default is too short to investigate with.
          extraOptions = [ "-retentionPeriod=${cfg.logs.retentionPeriod}" ];
        };

        services.victoriatraces = {
          enable = true;
          listenAddress = listenAddress tracesPort;
          retentionPeriod = cfg.traces.retentionPeriod;
        };

        services.grafana = {
          enable = true;

          # Datasources are declared here: the Victoria plugins, the Prometheus type upstream boards expect, and the built-in Jaeger datasource.
          declarativePlugins = [
            pkgs.grafanaPlugins.victoriametrics-metrics-datasource
            pkgs.grafanaPlugins.victoriametrics-logs-datasource
            pkgs.grafanaPlugins.grafana-metricsdrilldown-app
            pkgs.grafanaPlugins.grafana-polystat-panel
          ];

          settings = {
            server = {
              http_addr = cfg.listenAddress;
              http_port = route.upstreamPort;
              # Public identity stays literal, so links and redirects never leave it.
              domain = route.publicHost;
              root_url = route.publicUrl;
            };
            # Without OIDC, Access is the gate and anonymous viewers are read-only.
            "auth.anonymous" = {
              enabled = !cfg.oidc.enable;
              org_role = "Viewer";
            };
            # With OIDC the provider is the only interactive sign-in: the local form is
            # hidden and basic auth is off. Local accounts keep their data but cannot be
            # used to sign in, and `disableAutoLogin=true` on the URL restores the form for
            # one request if a configuration change ever breaks the provider path.
            auth = lib.mkIf cfg.oidc.enable {
              disable_login_form = true;
            };
            "auth.basic" = lib.mkIf cfg.oidc.enable {
              enabled = false;
            };
            "auth.generic_oauth" = lib.mkIf cfg.oidc.enable {
              enabled = true;
              name = oidcClient.providerName;
              client_id = oidcClient.clientId;
              client_secret = "$__file{/run/secrets/victoria_grafana_client_secret}";
              scopes = builtins.concatStringsSep " " oidcClient.scopes;
              auth_url = oidcClient.authorizationUrl;
              token_url = oidcClient.tokenUrl;
              api_url = oidcClient.userinfoUrl;
              use_pkce = true;
              allow_sign_up = true;
              # Keeps the existing user (and its roles) across a provider swap; the email
              # claim comes from the fleet's own identity provider.
              oauth_allow_insecure_email_lookup = true;
              # The strict role refuses sign-in for non-admins even when reached directly over the tailnet.
              groups_attribute_path = oidcClient.groupsClaim;
              role_attribute_path = "contains(${oidcClient.groupsClaim}, 'admins') && 'Admin' || ''";
              role_attribute_strict = true;
            };
            security = {
              # Anonymous viewers have nothing to protect; with OIDC the value comes from the host's secret file.
              secret_key =
                if cfg.oidc.enable then
                  "$__file{/run/secrets/victoria_grafana_secret_key}"
                else
                  "SW2YcwTIb9zpOOhoPsMm";
              # Seeded only while the account does not exist yet: a password already stored in
              # Grafana's database is not overwritten, so rotating it needs
              # `grafana cli admin reset-admin-password` on the host.
              admin_password = lib.mkIf (
                cfg.secretFiles.admin != null
              ) "$__file{/run/secrets/victoria_grafana_admin_password}";
              cookie_secure = true;
            };
            analytics = {
              reporting_enabled = false;
              check_for_updates = false;
            };
          };

          provision = {
            datasources.settings.datasources = [
              {
                name = "VictoriaMetrics";
                uid = prometheusUid;
                type = "prometheus";
                url = "http://127.0.0.1:${toString metricsPort}";
                access = "proxy";
                isDefault = true;
                jsonData = {
                  httpMethod = "POST";
                  manageAlerts = false;
                  timeInterval = cfg.scrapeInterval;
                };
              }
              {
                name = "VictoriaMetrics (MetricsQL)";
                uid = metricsqlUid;
                type = "victoriametrics-metrics-datasource";
                url = "http://127.0.0.1:${toString metricsPort}";
                access = "proxy";
              }
              {
                name = "VictoriaLogs";
                uid = logsUid;
                type = "victoriametrics-logs-datasource";
                url = "http://127.0.0.1:${toString logsPort}";
                access = "proxy";
              }
              {
                name = "VictoriaTraces";
                uid = tracesUid;
                type = "jaeger";
                url = "http://127.0.0.1:${toString tracesPort}/select/jaeger";
                access = "proxy";
              }
            ];

            dashboards.settings.providers = map (folder: {
              name = folder.dir;
              orgId = 1;
              folder = folder.title;
              type = "file";
              disableDeletion = false;
              updateIntervalSeconds = 60;
              allowUiUpdates = true;
              options.path = "${dashboards}/${folder.dir}";
            }) dashboardFolders;
          };
        };
      };
    };
}
