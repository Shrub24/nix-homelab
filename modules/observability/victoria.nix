# VictoriaMetrics, VictoriaLogs and VictoriaTraces. Ports close over their web-policy
# declarations; state lives on the root filesystem, bounded by retention. The front end is
# the separate `grafana` aspect, so a host selects both when it wants a UI.
{ ... }:
{
  flake.modules.nixos.victoria =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.services.victoria;

      catalog = config.repo.web.catalog or { };

      metricsPort = catalog.victoriametrics.endpoint.port;
      logsPort = catalog.victorialogs.endpoint.port;
      tracesPort = catalog.victoriatraces.endpoint.port;

      listenAddress = port: "${cfg.listenAddress}:${toString port}";
    in
    {
      options.services.victoria = {
        listenAddress = lib.mkOption {
          type = lib.types.str;
          default = "0.0.0.0";
          description = ''
            Interface the three stores bind. The fleet trusts the tailnet
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
      };

      config = {
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

      };
    };
}
