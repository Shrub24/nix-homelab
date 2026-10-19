# Victoria stack: the fleet's metrics, logs and traces store with its Grafana
# front end, placed on one host by aspect selection — the aspect has no enable
# gate, so importing it selects it.
#
# This file owns the store and its reader. What writes to it is the fleet
# collector contract's business; the interim producer is the node exporter the
# observability-agent aspect enables, plus the scrape job rendered below.
#
# Every listener port closes over its own web-policy declaration: the three
# ingest endpoints are private tailscale-only routes, the Grafana route is
# published behind Cloudflare Access, so a provider move is one policy edit and
# a port cannot drift from what a consumer dials.
#
# Grafana reads a provisional surface that Nix owns end to end: datasources, a
# small upstream dashboard collection, and — opt-in, because it needs the host's
# OIDC secret file and the canonical oauth2 client to exist first — Kanidm
# OIDC sign-in. Until it is opted in, Cloudflare Access stays the whole gate and
# Grafana serves read-only anonymous viewers.
#
# Data lives in the modules' StateDirectory under /var/lib, on the host's root
# filesystem: these units run as dynamic users under ProtectSystem=full, so a
# relocation to a bulk mount is a bind mount in front of that state directory
# rather than a storage-path flag. Retention is the volume control.
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

      # Per-client endpoints come from the intrinsic OIDC contract, so no
      # provider path is restated here; the client resolves only once the
      # identity policy enables it.
      oidcClient = config.services.identity.oidc.clients.grafana or null;

      # Datasource identity is declared once, here: the dashboards below address
      # these uids, and a provisioned dashboard that cannot resolve its
      # datasource is worse than no dashboard at all.
      prometheusUid = "victoriametrics";
      metricsqlUid = "victoriametrics-metricsql";
      logsUid = "victorialogs";
      tracesUid = "victoriatraces";

      # Upstream dashboards pinned to the releases that match the versions
      # nixpkgs ships (VictoriaMetrics 1.152.0, VictoriaLogs 1.52.0,
      # VictoriaTraces 0.11.1); the node board is grafana.com 1860 revision 45.
      # A board a flake input already ships is read from the input (`file`)
      # rather than fetched, so it moves with the pin that ships the server it
      # describes: the niks3 board is `inputs.niks3.dashboards.niks3`.
      #
      # Every board is rewritten on the way in so that it addresses *our*
      # datasources, never the ones its author had:
      #   - each panel's `datasource` gets both halves bound to the board's own
      #     store: the uid (upstream boards hardcode one — the logs board says
      #     "victoriametrics" throughout) *and* the type (upstream marks every
      #     panel `prometheus`, including the logs and traces ones, because that
      #     is the import placeholder they expect to be replaced);
      #   - each board's datasource *template variable* gets that uid as its
      #     selection, so the `$ds` / `${ds_prometheus}` references inside panels
      #     resolve there (the node board's variable is deliberately left named
      #     as upstream wrote it — it is a variable, not a placeholder);
      #   - grafana.com import placeholders (`$DS_PROMETHEUS`, `${DS_PROMETHEUS}`,
      #     the bare name) are substituted, since the file provider does not;
      #   - import metadata is dropped and each board gets a stable uid of its own.
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
          # Written for an `instance` label; this fleet's scrape job labels every
          # series with the canonical host ID instead (`host`), so the variable,
          # its query, every selector and every aggregation move to that name.
          #
          # The `Last GC` panel subtracts a comparison from the clock
          # (`time() - (gauge > 0)`), which on a server that has not collected yet
          # renders the epoch age — about 55 years — while the panel's own
          # description says it should read "none yet". A 1.15.0 server reports
          # the gauge as 0 rather than omitting it, so the mask has to divide:
          # the corrected form yields no data until a run completes, and the age
          # itself afterwards. Exact-string, so an upstream rewrite simply stops
          # matching instead of corrupting the query.
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
          # Written for the tailscale-mixin label set: its `cluster` dimension and
          # `tailscale_machine` label do not exist in this fleet, whose scrape job
          # labels every series with `host`. Both are rewritten here, not at the
          # producer, so the store keeps the one canonical machine label.
          extraJq = ''
            | del(.templating.list[]? | select(.name == "cluster"))
            | walk(if type == "string" then gsub("cluster=\"\\$cluster\"\\s*,?\\s*"; "") | gsub("tailscale_machine"; "host") else . end)
            | walk(if type == "object" then with_entries(.key |= gsub("tailscale_machine"; "host")) else . end)
          '';
        }
      ];

      # Dashboard folders are provisioned as one file provider each, so a board's
      # folder is the directory it is staged into; `dir` is the staging name.
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

      # Boards authored in this repository. They are copied verbatim: they already
      # address the store's datasource uid and carry their own stable uid.
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
      imports = [ ../identity/_oidc.nix ];

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
            Authenticate Grafana against the fleet's Kanidm provider instead of
            serving anonymous viewers. Requires both the canonical `grafana`
            oauth2 client in the identity policy and this host's OIDC secret
            file; the route stays behind Cloudflare Access either way.
          '';
        };

        secretFiles.oidc = secretHelpers.mkSecretFileOption "victoria-grafana-oidc-secrets";
      };

      config = {
        assertions = [
          {
            assertion = !cfg.oidc.enable || cfg.secretFiles.oidc != null;
            message = "services.victoria.secretFiles.oidc must be set when services.victoria.oidc.enable=true.";
          }
          {
            assertion = !cfg.oidc.enable || oidcClient != null;
            message = "services.victoria.oidc.enable requires the canonical 'grafana' oauth2 client in policy/identity.json.";
          }
        ];

        sops.secrets = lib.mkIf (cfg.oidc.enable && cfg.secretFiles.oidc != null) {
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
        };

        services.victoriametrics = {
          enable = true;
          listenAddress = listenAddress metricsPort;
          retentionPeriod = cfg.metrics.retentionPeriod;

          # Scrape the store's own endpoints, so the pipeline reports on itself
          # into the store it writes. Every producer host pushes its own metrics
          # through the telemetry aspect's collector instead — the store never
          # reaches into another host.
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
          # VictoriaLogs exposes no retention option in the module, and its
          # 7-day default is too short for the store to answer an investigation.
          extraOptions = [ "-retentionPeriod=${cfg.logs.retentionPeriod}" ];
        };

        services.victoriatraces = {
          enable = true;
          listenAddress = listenAddress tracesPort;
          retentionPeriod = cfg.traces.retentionPeriod;
        };

        services.grafana = {
          enable = true;

          # Datasources are declared here rather than clicked into a database:
          # the Victoria plugins, the plain Prometheus type upstream dashboards
          # and the drilldown app expect, and the built-in Jaeger datasource
          # against VictoriaTraces' Jaeger-compatible API.
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
              # The edge terminates TLS and Access. Public identity stays
              # literal so links and redirects never leave it.
              domain = route.publicHost;
              root_url = route.publicUrl;
            };
            # Without OIDC, Cloudflare Access is the whole gate and Grafana
            # serves read-only anonymous viewers. With it, every request carries
            # a real Kanidm identity and the role comes from group membership.
            "auth.anonymous" = {
              enabled = !cfg.oidc.enable;
              org_role = "Viewer";
            };
            "auth.generic_oauth" = lib.mkIf cfg.oidc.enable {
              enabled = true;
              name = "Kanidm";
              client_id = oidcClient.clientId;
              client_secret = "$__file{/run/secrets/victoria_grafana_client_secret}";
              scopes = "openid profile email groups_name";
              auth_url = oidcClient.authorizationUrl;
              token_url = oidcClient.tokenUrl;
              api_url = oidcClient.userinfoUrl;
              use_pkce = true;
              allow_sign_up = true;
              # Kanidm releases group names through the `groups` claim; the
              # strict role leaves every non-admin without a role, so the
              # provider refuses the sign-in even if a request reaches the
              # origin directly over the tailnet.
              groups_attribute_path = "groups";
              role_attribute_path = "contains(groups, 'admins') && 'Admin' || ''";
              role_attribute_strict = true;
            };
            security = {
              # Grafana's own cookie and datasource encryption material. With
              # anonymous viewers there is nothing to protect, so the documented
              # pre-26.05 default is stated deliberately; with OIDC sign-in the
              # value comes from the host's secret file.
              secret_key =
                if cfg.oidc.enable then
                  "$__file{/run/secrets/victoria_grafana_secret_key}"
                else
                  "SW2YcwTIb9zpOOhoPsMm";
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
