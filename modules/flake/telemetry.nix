# Fleet policy over nix-fleet's telemetry contract: the store as destination, URLs derived from the web catalog.
# Derived inside the NixOS module: `repo` is not visible at this flake-parts level.
{ inputs, ... }:
let
  collectorPolicy =
    { config, lib, ... }:
    let
      tracesUrl = config.repo.web.catalog."victoriatraces".endpoint.url;

      # The route decides who may be reached; these views decide what each receives. Payload shaping only:
      # a producer that can reach the listener reaches all three audiences.
      aiRoute = "ai";
      routePipeline = "traces/route-${aiRoute}";
      routeReceiver = "otlp/route-${aiRoute}";
      exporterKey =
        destination:
        let
          protocol = config.services.telemetry.destinations.${destination}.protocol;
          component = if protocol == "prometheus-remote-write" then "prometheusremotewrite" else "otlphttp";
        in
        "${component}/route-${aiRoute}-${destination}";
      metricRoutePipeline = "metrics/route-${aiRoute}";
      logRoutePipeline = "logs/route-${aiRoute}";
      markerProcessors = [ "transform/route-${aiRoute}-marker" ];
      logRedactionProcessors = [ "transform/output-view-logs" ];
      generalRouteTagRemoval = [ "transform/drop-general-route-marker" ];
      generalLogProcessors = logRedactionProcessors ++ generalRouteTagRemoval;
      logProcessors = logRedactionProcessors ++ markerProcessors;
      aiRouteMembers = {
        traces = [
          "victoriatraces"
          "langfuse"
          "latitude"
        ];
        metrics = [ "victoriametrics" ];
        logs = [ "victorialogs" ];
      };

      # Inherits the route's processors. `batch` is absent on purpose: the export queue is the acknowledgement boundary.
      richProcessors =
        config.services.opentelemetry-collector.settings.service.pipelines.${routePipeline}.processors;
      leanProcessors = [
        "transform/output-view-lean"
        "filter/output-view-lean-events"
      ];
      latitudeProcessors = [ "transform/output-view-latitude" ];
      langfuseProcessors = [ "transform/output-view-langfuse" ];
      # Langfuse's mapping runs on the rich leg only.
      richWithoutLangfuse = lib.subtractLists langfuseProcessors richProcessors;

      # Deny list of known content carriers, so unseen instrumentation still reaches the store.
      # A new producer's carriers must be added here, not assumed covered.
      leanAttributeKeys = [
        "gen_ai.input.messages"
        "gen_ai.output.messages"
        "gen_ai.system_instructions"
        "gen_ai.tool.call.arguments"
        "gen_ai.tool.call.result"
        "gen_ai.prompt"
        "gen_ai.completion"
        "pi.user_prompt"
        "input.value"
        "output.value"
      ];
      leanAttributePatterns = [
        "^gen_ai\\.(prompt|completion)\\..*"
        "^llm\\.(input_messages|output_messages)\\..*"
      ];
      # OTTL escapes backslashes; escaping here keeps the patterns readable as regexes.
      ottl = lib.escape [ "\\" ];
      # Content-bearing events echo provider payloads; the span's error attributes survive.
      leanEventCondition = ''IsMatch(spanevent.name, "${ottl "^(gen_ai\\..*|exception)$"}")'';
      leanStatements =
        map (key: ''delete_key(span.attributes, "${key}")'') leanAttributeKeys
        ++ map (pattern: ''delete_matching_keys(span.attributes, "${ottl pattern}")'') leanAttributePatterns
        ++ [ ''delete_matching_keys(span.attributes, "${ottl "^(langfuse|latitude)\\..*"}")'' ];

      # Latitude consumes canonical GenAI attributes unchanged; 1.36 events fill them only when absent.
      inferenceEvent = ''spanevent.name == "gen_ai.client.inference.operation.details"'';
      canonicalMessageGate = ''span.attributes["gen_ai.input.messages"] == nil and span.attributes["gen_ai.output.messages"] == nil'';
      latitudeStatements = [
        ''set(span.attributes["gen_ai.prompt"], spanevent.attributes["gen_ai.input.messages"]) where ${inferenceEvent} and spanevent.attributes["gen_ai.input.messages"] != nil and ${canonicalMessageGate} and span.attributes["gen_ai.prompt"] == nil''
        ''set(span.attributes["gen_ai.completion"], spanevent.attributes["gen_ai.output.messages"]) where ${inferenceEvent} and spanevent.attributes["gen_ai.output.messages"] != nil and ${canonicalMessageGate} and span.attributes["gen_ai.completion"] == nil''
        ''set(span.attributes["gen_ai.system_instructions"], spanevent.attributes["gen_ai.system_instructions"]) where ${inferenceEvent} and spanevent.attributes["gen_ai.system_instructions"] != nil and span.attributes["gen_ai.system_instructions"] == nil''
      ];

      # Copies fill only absent keys; JSON encoding and span-kind logic stay with the exporter.
      fillIfAbsent =
        dst: src:
        let
          value = ''span.attributes["${src}"]'';
        in
        ''set(span.attributes["${dst}"], ${value}) where span.attributes["${dst}"] == nil and ${value} != nil and ${value} != ""'';
      langfuseMetadataFields = [
        {
          key = "pi_run_kind";
          src = "pi.run.kind";
        }
        {
          key = "pi_session_mode";
          src = "pi.session.mode";
        }
        {
          key = "pi_session_name";
          src = "pi.session.name";
        }
        {
          key = "pi_agent_role";
          src = "pi.agent.role";
        }
        {
          key = "pi_agent_label";
          src = "pi.agent.label";
        }
        {
          key = "pi_agent_run_id";
          src = "pi.agent.run_id";
        }
        {
          key = "pi_agent_owner_session_id";
          src = "pi.agent.owner_session_id";
        }
        {
          key = "pi_agent_workspace_id";
          src = "pi.agent.workspace_id";
        }
      ];
      # Cut to 256 characters: the exporter counts UTF-16 units, so a byte cut matches only for ASCII.
      langfuseMetadataStatements = lib.concatMap (
        { key, src }:
        let
          dst = "langfuse.trace.metadata.${key}";
          value = ''span.attributes["${src}"]'';
          absent = ''span.attributes["${dst}"] == nil and ${value} != nil and ${value} != ""'';
        in
        [
          ''set(span.attributes["${dst}"], ${value}) where ${absent} and Len(${value}) <= 256''
          ''set(span.attributes["${dst}"], Substring(${value}, 0, 256, true)) where ${absent} and Len(${value}) > 256''
        ]
      ) langfuseMetadataFields;
      langfuseTagAbsentKey = "collector.langfuse_tags_absent";
      langfuseTagFields = [
        {
          prefix = "run-kind";
          src = "pi.run.kind";
        }
        {
          prefix = "mode";
          src = "pi.session.mode";
        }
        {
          prefix = "role";
          src = "pi.agent.role";
        }
        {
          prefix = "agent";
          src = "pi.agent.label";
        }
      ];
      # The absence of the array gates every append, so the marker is captured before the first one.
      langfuseTagStatements = [
        ''set(span.attributes["${langfuseTagAbsentKey}"], true) where span.attributes["langfuse.trace.tags"] == nil''
      ]
      ++ map (
        { prefix, src }:
        let
          value = ''span.attributes["${src}"]'';
          tag = ''Concat(["${prefix}:", ${value}], "")'';
        in
        ''append(span.attributes["langfuse.trace.tags"], ${tag}) where span.attributes["${langfuseTagAbsentKey}"] == true and ${value} != nil and ${value} != "" and Len(${tag}) <= 200''
      ) langfuseTagFields
      ++ [ ''delete_key(span.attributes, "${langfuseTagAbsentKey}")'' ];
      langfuseCopyStatements = [
        (fillIfAbsent "langfuse.trace.name" "pi.session.name")
        (fillIfAbsent "langfuse.observation.output" "gen_ai.output.messages")
        (fillIfAbsent "langfuse.observation.input" "gen_ai.tool.call.arguments")
        (fillIfAbsent "langfuse.observation.output" "gen_ai.tool.call.result")
      ];
      # Dropped only where the observation key is present, so no content is lost.
      langfuseDuplicateStatements = [
        ''delete_key(span.attributes, "gen_ai.input.messages") where span.attributes["langfuse.observation.input"] != nil''
        ''delete_key(span.attributes, "gen_ai.system_instructions") where span.attributes["langfuse.observation.input"] != nil''
        ''delete_key(span.attributes, "gen_ai.tool.definitions") where span.attributes["langfuse.observation.input"] != nil''
        ''delete_key(span.attributes, "gen_ai.tool.call.arguments") where span.attributes["langfuse.observation.input"] != nil''
        ''delete_key(span.attributes, "pi.user_prompt") where span.attributes["langfuse.observation.input"] != nil''
        ''delete_key(span.attributes, "gen_ai.output.messages") where span.attributes["langfuse.observation.output"] != nil''
        ''delete_key(span.attributes, "gen_ai.tool.call.result") where span.attributes["langfuse.observation.output"] != nil''
      ];
      langfuseStatements =
        langfuseCopyStatements
        ++ langfuseMetadataStatements
        ++ langfuseTagStatements
        ++ [ ''delete_matching_keys(span.attributes, "${ottl "^latitude\\..*"}")'' ]
        ++ langfuseDuplicateStatements;
      latitudeSpanStatements = [
        ''set(span.attributes["latitude.capture.name"], span.name) where span.attributes["gen_ai.operation.name"] == "invoke_agent" and span.attributes["latitude.capture.name"] == nil''
        ''delete_matching_keys(span.attributes, "${ottl "^langfuse\\..*"}")''
      ];

      aiLaneActive = config.services.telemetry.routes ? ${aiRoute};

      # Expected composition as data: the guard compares the effective settings against it, since a native override would defeat the declaration.
      outputViews = {
        general = {
          signal = "traces";
          pipeline = "traces";
          receiver = "otlp";
          instanceRoute = null;
          destinations = [ "victoriatraces" ];
          exporterOptions = { };
          requiredProcessors = generalRouteTagRemoval;
          forbiddenProcessors = markerProcessors;
        };
        generalMetrics = {
          signal = "metrics";
          pipeline = "metrics";
          receiver = "otlp";
          instanceRoute = null;
          destinations = [ "victoriametrics" ];
          exporterOptions = { };
          requiredProcessors = generalRouteTagRemoval;
          forbiddenProcessors = markerProcessors;
        };
        generalLogs = {
          signal = "logs";
          pipeline = "logs";
          receiver = "otlp";
          instanceRoute = null;
          destinations = [ "victorialogs" ];
          exporterOptions = { };
          requiredProcessors = generalLogProcessors;
          forbiddenProcessors = markerProcessors;
        };
        rich = {
          signal = "traces";
          pipeline = routePipeline;
          receiver = routeReceiver;
          instanceRoute = aiRoute;
          destinations = [ "langfuse" ];
          exporterOptions = { };
          requiredProcessors = markerProcessors ++ langfuseProcessors;
          forbiddenProcessors = leanProcessors ++ latitudeProcessors;
        };
        lean = {
          signal = "traces";
          pipeline = "${routePipeline}-lean";
          receiver = routeReceiver;
          instanceRoute = aiRoute;
          destinations = [ "victoriatraces" ];
          exporterOptions = { };
          requiredProcessors = markerProcessors ++ leanProcessors;
          forbiddenProcessors = latitudeProcessors ++ langfuseProcessors;
        };
        latitude = {
          signal = "traces";
          pipeline = "${routePipeline}-latitude";
          receiver = routeReceiver;
          instanceRoute = aiRoute;
          destinations = [ "latitude" ];
          exporterOptions.compression = "none";
          requiredProcessors = markerProcessors ++ latitudeProcessors;
          forbiddenProcessors = leanProcessors ++ langfuseProcessors;
        };
        metrics = {
          signal = "metrics";
          pipeline = metricRoutePipeline;
          receiver = routeReceiver;
          instanceRoute = aiRoute;
          destinations = [ "victoriametrics" ];
          exporterOptions = { };
          requiredProcessors = markerProcessors;
          forbiddenProcessors = [ ];
        };
        logs = {
          signal = "logs";
          pipeline = logRoutePipeline;
          receiver = routeReceiver;
          instanceRoute = aiRoute;
          destinations = [ "victorialogs" ];
          exporterOptions = { };
          requiredProcessors = logProcessors;
          forbiddenProcessors = [ ];
        };
      };
    in
    {
      # Internal: consumed by the composition guard's contract test.
      options.fleet.telemetry.outputViews = lib.mkOption {
        type = lib.types.anything;
        default = { };
        internal = true;
        description = "Expected output views for the AI telemetry route, as data for the composition guard.";
      };

      config = {
        fleet.telemetry.outputViews = lib.mkIf aiLaneActive outputViews;

        assertions = [
          {
            assertion =
              !aiLaneActive
              ||
                lib.all
                  (
                    signal:
                    lib.sort (a: b: a < b) aiRouteMembers.${signal}
                    == lib.sort (a: b: a < b) (config.services.telemetry.routes.${aiRoute}.pipelines.${signal} or [ ])
                  )
                  [
                    "traces"
                    "metrics"
                    "logs"
                  ];
            message = ''
              telemetry: route '${aiRoute}' destination membership does not match the checked
              traces/metrics/logs views in modules/flake/telemetry.nix.
            '';
          }
        ];

        # VictoriaTraces' OTLP path is signal-specific; the default trailing /v1/traces append is wrong.
        services.otel-collector.exporterExtra.victoriatraces.traces_endpoint =
          "${tracesUrl}/insert/opentelemetry/v1/traces";
        services.otel-collector.exporterExtra.victorialogs.logs_endpoint = "${
          config.repo.web.catalog."victorialogs".endpoint.url
        }/insert/opentelemetry/v1/logs";

        services.otel-collector.exporterExtra.langfuse.headers."x-langfuse-ingestion-version" = "4";
        # Org-wide keys: unscoped producer spans need a project default at ingest.
        services.otel-collector.exporterExtra.latitude = {
          headers."X-Latitude-Project" = "shrublab";
          # This ingest version does not decompress gzip before decoding protobuf.
          compression = "none";
        };

        # Off: 8888 is omniroute's API. The route pipeline is replaced, not extended, and
        # branch-only processors live in settings.processors.
        services.opentelemetry-collector.settings = lib.mkMerge [
          {
            service.telemetry.metrics.level = "none";
            processors = {
              "transform/drop-general-route-marker" = {
                error_mode = "ignore";
                trace_statements = [
                  {
                    context = "span";
                    statements = [ ''delete_key(span.attributes, "telemetry.route")'' ];
                  }
                  {
                    context = "resource";
                    statements = [ ''delete_key(resource.attributes, "telemetry.route")'' ];
                  }
                ];
                metric_statements = [
                  {
                    context = "datapoint";
                    statements = [ ''delete_key(datapoint.attributes, "telemetry.route")'' ];
                  }
                  {
                    context = "resource";
                    statements = [ ''delete_key(resource.attributes, "telemetry.route")'' ];
                  }
                ];
                log_statements = [
                  {
                    context = "resource";
                    statements = [ ''delete_key(resource.attributes, "telemetry.route")'' ];
                  }
                ];
              };
              "transform/output-view-logs" = {
                error_mode = "ignore";
                log_statements = [
                  {
                    context = "log";
                    statements = [
                      ''set(log.attributes["trace_flags"], log.flags)''
                      ''keep_keys(log.attributes, ["trace_flags"])''
                    ];
                  }
                  {
                    context = "resource";
                    statements = [
                      ''keep_keys(resource.attributes, ["telemetry.route", "host.name", "service.name", "deployment.environment.name"])''
                    ];
                  }
                  {
                    context = "scope";
                    statements = [ "keep_keys(scope.attributes, [])" ];
                  }
                ];
              };
            };
            service.pipelines = {
              traces.processors = lib.mkAfter generalRouteTagRemoval;
              "traces/ingress".processors = lib.mkAfter generalRouteTagRemoval;
              metrics.processors = lib.mkAfter generalRouteTagRemoval;
              "metrics/ingress".processors = lib.mkAfter generalRouteTagRemoval;
              logs.processors = lib.mkAfter generalLogProcessors;
              "logs/ingress".processors = lib.mkAfter generalLogProcessors;
            };
          }
          (lib.mkIf aiLaneActive {
            processors = {
              "transform/output-view-lean" = {
                error_mode = "ignore";
                trace_statements = [
                  {
                    context = "span";
                    statements = leanStatements;
                  }
                ];
              };
              "filter/output-view-lean-events" = {
                error_mode = "ignore";
                trace_conditions = [ leanEventCondition ];
              };
              "transform/output-view-latitude" = {
                error_mode = "ignore";
                trace_statements = [
                  {
                    context = "spanevent";
                    statements = latitudeStatements;
                  }
                  {
                    context = "span";
                    statements = latitudeSpanStatements;
                  }
                ];
              };
              "transform/output-view-langfuse" = {
                error_mode = "ignore";
                trace_statements = [
                  {
                    context = "span";
                    statements = langfuseStatements;
                  }
                ];
              };
              "transform/route-${aiRoute}-marker" = {
                error_mode = "ignore";
                trace_statements = [
                  {
                    context = "span";
                    statements = [ ''delete_key(span.attributes, "telemetry.route")'' ];
                  }
                  {
                    context = "resource";
                    statements = [ ''set(resource.attributes["telemetry.route"], "ai")'' ];
                  }
                ];
                metric_statements = [
                  {
                    context = "datapoint";
                    statements = [ ''delete_key(datapoint.attributes, "telemetry.route")'' ];
                  }
                  {
                    context = "resource";
                    statements = [ ''set(resource.attributes["telemetry.route"], "ai")'' ];
                  }
                ];
                log_statements = [
                  {
                    context = "log";
                    statements = [ ''delete_key(log.attributes, "telemetry.route")'' ];
                  }
                  {
                    context = "resource";
                    statements = [ ''set(resource.attributes["telemetry.route"], "ai")'' ];
                  }
                ];
              };
            };

            service.pipelines = {
              # The rich view: the generated pipeline minus what the sibling views export.
              ${routePipeline} = {
                processors = lib.mkAfter (markerProcessors ++ langfuseProcessors);
                exporters = lib.mkForce [ (exporterKey "langfuse") ];
              };

              "${routePipeline}-lean" = {
                receivers = [ routeReceiver ];
                processors = richWithoutLangfuse ++ leanProcessors;
                exporters = [ (exporterKey "victoriatraces") ];
              };

              # Bridges the deployed Latitude image's legacy message format.
              "${routePipeline}-latitude" = {
                receivers = [ routeReceiver ];
                processors = richWithoutLangfuse ++ latitudeProcessors;
                exporters = [ (exporterKey "latitude") ];
              };

              ${metricRoutePipeline} = {
                processors = lib.mkAfter markerProcessors;
                exporters = lib.mkForce [ (exporterKey "victoriametrics") ];
              };
              ${logRoutePipeline} = {
                processors = lib.mkAfter logProcessors;
                exporters = lib.mkForce [ (exporterKey "victorialogs") ];
              };
            };
          })
        ];
      };
    };
in
{
  # Vocabulary plus policy; starts nothing. A host ships a signal by selecting its lane.
  flake.modules.nixos.telemetry =
    {
      config,
      lib,
      options,
      ...
    }:
    let
      catalog = config.repo.web.catalog;
      tracesUrl = catalog."victoriatraces".endpoint.url;
      # Legs are gated on the backend being placed here (its header secret exists only then) and on
      # colocation, since a remote host must not dial the loopback endpoint.
      runsLangfuse = lib.hasAttrByPath [ "services" "langfuse" ] options;
      runsLatitude = lib.hasAttrByPath [ "services" "latitude" ] options;
      colocatedWithBackends = lib.hasPrefix "http://127.0.0.1" catalog.langfuse.endpoint.url;
      langfuseActive = runsLangfuse && colocatedWithBackends;
      latitudeActive = runsLatitude && colocatedWithBackends;
      fanoutDestinations =
        lib.optionalAttrs langfuseActive {
          langfuse = {
            protocol = "otlp-http";
            endpoint = "${catalog.langfuse.endpoint.url}/api/public/otel";
            signals = [ "traces" ];
            headers.authorization = {
              secret = "langfuse";
              prefix = "Basic ";
            };
          };
        }
        // lib.optionalAttrs latitudeActive {
          latitude = {
            protocol = "otlp-http";
            endpoint = "${catalog."latitude-ingest".endpoint.url}";
            signals = [ "traces" ];
            headers.authorization = {
              secret = "latitude";
              prefix = "Bearer ";
            };
          };
        };
    in
    {
      imports = [ inputs.nix-fleet.modules.nixos.telemetry ];

      services.telemetry = {
        destinations = {
          victoriametrics = {
            protocol = "prometheus-remote-write";
            endpoint = "${catalog."victoriametrics".endpoint.url}/api/v1/write";
            signals = [ "metrics" ];
          };
          victoriatraces = {
            protocol = "otlp-http";
            endpoint = tracesUrl;
            signals = [ "traces" ];
          };
          victorialogs = {
            protocol = "otlp-http";
            endpoint = "${catalog."victorialogs".endpoint.url}/insert/opentelemetry/v1/logs";
            signals = [ "logs" ];
          };
        }
        // fanoutDestinations;

        # Routing separation, not access control: the route adds no authentication.
        otlp.signals = [ "logs" ];
        pipelines = {
          traces = [ "victoriatraces" ];
          metrics = [ "victoriametrics" ];
          logs = [ "victorialogs" ];
        };

        secretFiles =
          lib.optionalAttrs langfuseActive {
            langfuse = ../../secrets/services/langfuse.yaml;
          }
          // lib.optionalAttrs latitudeActive {
            latitude = ../../secrets/services/telemetry.yaml;
          };
        secretKeys =
          lib.optionalAttrs langfuseActive {
            langfuse = "otel/basic";
          }
          // lib.optionalAttrs latitudeActive {
            latitude = "latitude/api_key";
          };

        # Explicit licence: the contract refuses an empty log allowlist otherwise.
        journald = {
          enable = true;
          includeAll = true;
          sink.endpoint = "${catalog."victorialogs".endpoint.url}/insert/jsonline";
        };
      };
    };

  flake.modules.nixos.telemetry-metrics = {
    imports = [ inputs.nix-fleet.modules.nixos.telemetry-metrics ];
  };

  flake.modules.nixos.telemetry-logs = {
    imports = [ inputs.nix-fleet.modules.nixos.telemetry-logs ];
  };

  flake.modules.nixos.telemetry-otlp = {
    imports = [
      inputs.nix-fleet.modules.nixos.telemetry-otlp
      collectorPolicy
    ];
  };
}
