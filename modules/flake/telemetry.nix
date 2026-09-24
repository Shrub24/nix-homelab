# Telemetry aspects: the fleet's conventions over nix-fleet's host-local
# telemetry contract. Upstream splits the surface — `telemetry` is the
# implementation-agnostic vocabulary (scrape sources, OTLP admission, journald
# shipping, remote destinations) and starts nothing, while a *lane* composes the
# contract with the fleet's default realization for one signal. This contributor
# binds our aspect names over those lanes and supplies the fleet's policy: the
# store as the metrics, traces and log destination, every URL derived from the
# web catalog, so moving the store or a listener port stays one policy edit and
# no consumer restates it.
#
# The catalog is a NixOS option, so the derivation happens inside the NixOS
# module: reading it at this outer flake-parts level would look for `repo` on
# the flake config.
{ inputs, ... }:
let
  # Collector-scoped policy. `services.otel-collector` belongs to a collector
  # realization, so this half lives with our OTLP lane rather than in the
  # vocabulary every telemetry host composes.
  collectorPolicy =
    { config, lib, ... }:
    let
      tracesUrl = config.repo.web.catalog."victoriatraces".endpoint.url;

      # Output views for the AI lane. One route is one input audience, so the
      # route declaration decides *who may be reached* (its destination
      # membership, one exporter instance per member) and these pipelines decide
      # *what each of them receives*. Three audiences, three payloads: the
      # analysis backends take the session with its vendor keys mapped from the
      # canonical carriers (D-088), the operational store takes the same spans
      # without their content carriers. Every view consumes
      # the same route receiver, so this is payload shaping, not an audience
      # boundary — a producer that can reach the listener reaches all three.
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

      # A view inherits the rendered route pipeline's processor list rather than
      # restating it, so the fleet's collector policy (the memory limiter) stays
      # one definition. `batch` is deliberately absent from that policy: the
      # persistent export queue is the acknowledgement boundary, and a batch
      # processor in front of it would acknowledge before the queue owns the
      # data.
      richProcessors =
        config.services.opentelemetry-collector.settings.service.pipelines.${routePipeline}.processors;
      leanProcessors = [
        "transform/output-view-lean"
        "filter/output-view-lean-events"
      ];
      latitudeProcessors = [ "transform/output-view-latitude" ];
      langfuseProcessors = [ "transform/output-view-langfuse" ];
      # The rich pipeline's processors are inherited by the sibling legs, so the
      # Langfuse mapping is filtered out of their copy; it runs on the rich leg only.
      richWithoutLangfuse = lib.subtractLists langfuseProcessors richProcessors;

      # Content carriers the operational store does not keep: the payload fields
      # the LLM backends parse (canonical and legacy families), tool
      # arguments and results, and the generic value conventions. A deny list
      # rather than an allow list, so instrumentation this fleet has not seen yet
      # still reaches the store — every entry here is a known carrier, and a
      # producer whose carriers are missing from it must be added below rather
      # than assumed covered.
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
      # An OTTL string literal escapes backslashes, so a regex's `\.` is written
      # `\\.` in the emitted statement; escaping at the render site keeps the
      # patterns above readable as the regexes they are.
      ottl = lib.escape [ "\\" ];
      # Content-bearing span events: the GenAI families and the SDK exception
      # event, whose message and stacktrace echo provider payloads. The span's
      # own error attributes and status survive, so the store keeps the signal
      # without the payload.
      leanEventCondition = ''IsMatch(spanevent.name, "${ottl "^(gen_ai\\..*|exception)$"}")'';
      leanStatements =
        map (key: ''delete_key(span.attributes, "${key}")'') leanAttributeKeys
        ++ map (pattern: ''delete_matching_keys(span.attributes, "${ottl pattern}")'') leanAttributePatterns
        # Foreign vendor keys: VictoriaTraces reads neither backend's attributes.
        ++ [ ''delete_matching_keys(span.attributes, "${ottl "^(langfuse|latitude)\\..*"}")'' ];

      # Latitude's current OTLP docs consume the canonical GenAI span attributes,
      # including parts-based input/output messages and system instructions. Keep
      # them unchanged. Older 1.36 inference events can be materialized onto the
      # containing span only when canonical attributes are absent.
      inferenceEvent = ''spanevent.name == "gen_ai.client.inference.operation.details"'';
      canonicalMessageGate = ''span.attributes["gen_ai.input.messages"] == nil and span.attributes["gen_ai.output.messages"] == nil'';
      latitudeStatements = [
        ''set(span.attributes["gen_ai.prompt"], spanevent.attributes["gen_ai.input.messages"]) where ${inferenceEvent} and spanevent.attributes["gen_ai.input.messages"] != nil and ${canonicalMessageGate} and span.attributes["gen_ai.prompt"] == nil''
        ''set(span.attributes["gen_ai.completion"], spanevent.attributes["gen_ai.output.messages"]) where ${inferenceEvent} and spanevent.attributes["gen_ai.output.messages"] != nil and ${canonicalMessageGate} and span.attributes["gen_ai.completion"] == nil''
        ''set(span.attributes["gen_ai.system_instructions"], spanevent.attributes["gen_ai.system_instructions"]) where ${inferenceEvent} and spanevent.attributes["gen_ai.system_instructions"] != nil and span.attributes["gen_ai.system_instructions"] == nil''
      ];

      # Direct vendor-attribute rows: a Langfuse or Latitude key the collector can
      # rebuild by copying one canonical field. The exporter still writes these, so
      # every copy fills only an absent key. Rows that need JSON encoding, span-kind
      # knowledge or another span's data stay with the exporter (pi-otel
      # docs/attribute-mapping.md, "Rebuilding a vendor key").
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
      # Copied, then cut to 256 characters: the exporter's own cut is applied in
      # UTF-16 units, so the collector's byte cut matches it only for ASCII. The
      # copy runs only when the exporter did not already write the key.
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
      # The tags are appended one by one, so the array's absence is captured before
      # the first append and gates every append; the marker is then removed. A span
      # that already carries the exporter's array is left as it is.
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
      # Canonical content the Langfuse leg reads through its own observation keys.
      # Dropped only where that key is present, so no content is lost if the
      # exporter omitted the vendor key.
      langfuseDuplicateStatements = [
        ''delete_key(span.attributes, "gen_ai.input.messages") where span.attributes["langfuse.observation.input"] != nil''
        ''delete_key(span.attributes, "gen_ai.system_instructions") where span.attributes["langfuse.observation.input"] != nil''
        ''delete_key(span.attributes, "gen_ai.tool.definitions") where span.attributes["langfuse.observation.input"] != nil''
        ''delete_key(span.attributes, "gen_ai.tool.call.arguments") where span.attributes["langfuse.observation.input"] != nil''
        ''delete_key(span.attributes, "pi.user_prompt") where span.attributes["langfuse.observation.input"] != nil''
        ''delete_key(span.attributes, "gen_ai.output.messages") where span.attributes["langfuse.observation.output"] != nil''
        ''delete_key(span.attributes, "gen_ai.tool.call.result") where span.attributes["langfuse.observation.output"] != nil''
      ];
      # Copies run before any pruning, so a pruned canonical key was already copied.
      langfuseStatements =
        langfuseCopyStatements
        ++ langfuseMetadataStatements
        ++ langfuseTagStatements
        ++ [ ''delete_matching_keys(span.attributes, "${ottl "^latitude\\..*"}")'' ]
        ++ langfuseDuplicateStatements;
      # Latitude's root span takes its capture name from the span name, and the
      # Langfuse keys are foreign to this leg.
      latitudeSpanStatements = [
        ''set(span.attributes["latitude.capture.name"], span.name) where span.attributes["gen_ai.operation.name"] == "invoke_agent" and span.attributes["latitude.capture.name"] == nil''
        ''delete_matching_keys(span.attributes, "${ottl "^langfuse\\..*"}")''
      ];

      # The lane exists only where the route does; a host that selects the OTLP
      # lane without declaring it gets no views and no processors.
      aiLaneActive = config.services.telemetry.routes ? ${aiRoute};

      # The expected composition, as data: a native pipeline override means the
      # declaration alone proves nothing, so the guard reads the effective
      # settings and compares them against this.
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
      # Read-only, internal: this is the composition's own description, consumed
      # by the contract test that runs nix-fleet's composition guard against the
      # effective settings. It is not a user-facing seam.
      options.fleet.telemetry.outputViews = lib.mkOption {
        type = lib.types.anything;
        default = { };
        internal = true;
        description = "Expected output views for the AI telemetry route, as data for the composition guard.";
      };

      config = {
        fleet.telemetry.outputViews = lib.mkIf aiLaneActive outputViews;

        # The composition partitions the route's members, so a route that names
        # different destinations must extend this rather than be silently split.
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

        # VictoriaTraces' OTLP ingest path is signal-specific, so the exporter
        # must not lean on the default trailing /v1/traces append.
        services.otel-collector.exporterExtra.victoriatraces.traces_endpoint =
          "${tracesUrl}/insert/opentelemetry/v1/traces";
        services.otel-collector.exporterExtra.victorialogs.logs_endpoint = "${
          config.repo.web.catalog."victorialogs".endpoint.url
        }/insert/opentelemetry/v1/logs";

        services.otel-collector.exporterExtra.langfuse.headers."x-langfuse-ingestion-version" = "4";
        # This Latitude deployment has org-wide keys; unscoped producer spans
        # need a project default at the shared ingest boundary.
        services.otel-collector.exporterExtra.latitude = {
          headers."X-Latitude-Project" = "shrublab";
          # This ingest version decodes protobuf without decompressing gzip.
          compression = "none";
        };

        # Collector settings. The internal Prometheus reader defaults to
        # 127.0.0.1:8888, which is omniroute's API port on this fleet — the
        # collector died at startup on home-forge with `bind: address already in
        # use`. Its own metrics are not consumed by anything (the store scrapes
        # its own endpoints), so turn the metrics pipeline off instead of choosing
        # a different port for a listener nobody reads.
        #
        # The views: the generated route pipeline is replaced rather than
        # extended, because its exporter list is the whole route — a member left
        # there while a view also exports it would be assigned two output paths,
        # two queues and two copies to one backend. Branch-only processors are
        # defined in `settings.processors` and named by the pipelines that need
        # them; `services.otel-collector.processors` is not the place for them,
        # because every generated pipeline, metrics included, carries that list.
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
              # The rich view stays the generated pipeline, minus the members the
              # sibling views below export: the analysis backends that parse a
              # session live here, with the Langfuse mapping applied (D-088).
              ${routePipeline} = {
                processors = lib.mkAfter (markerProcessors ++ langfuseProcessors);
                exporters = lib.mkForce [ (exporterKey "langfuse") ];
              };

              # The operational store's copy: the same spans, carriers removed.
              "${routePipeline}-lean" = {
                receivers = [ routeReceiver ];
                processors = richWithoutLangfuse ++ leanProcessors;
                exporters = [ (exporterKey "victoriatraces") ];
              };

              # The version-scoped carrier bridge for the deployed Latitude image.
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
  # Vocabulary plus fleet policy. Selecting it starts no provider; a host ships
  # a signal by also selecting that signal's lane.
  flake.modules.nixos.telemetry =
    { config, lib, ... }:
    let
      catalog = config.repo.web.catalog;
      tracesUrl = catalog."victoriatraces".endpoint.url;
      # The LLM-observability legs (D-074) are destination policy, gated on two
      # things ANDed per leg: the backend's own sops file exists (the contract's
      # headers throw on an unbound secret, so the leg is absent until the
      # two-step bootstrap — the tailscale pattern) and this host is colocated
      # with the backends (the catalog's endpoint is loopback exactly where the
      # host serves the backend, so a backend move drags its exporter leg with
      # it and remote hosts never dial a dead loopback port). Langfuse's
      # credential is the pair Langfuse itself seeds at first-run init from the
      # same file — one source, consumed on both sides; Latitude's key is
      # UI-issued (telemetry.yaml).
      hasLangfuseSecrets = builtins.pathExists ../../secrets/services/langfuse.yaml;
      hasLatitudeSecrets = builtins.pathExists ../../secrets/services/telemetry.yaml;
      colocatedWithBackends = lib.hasPrefix "http://127.0.0.1" catalog.langfuse.endpoint.url;
      langfuseActive = hasLangfuseSecrets && colocatedWithBackends;
      latitudeActive = hasLatitudeSecrets && colocatedWithBackends;
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
          # Producers push their own metrics; the store keeps only its
          # self-scrape job rather than reaching into every host.
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

        # The general route carries fleet telemetry to the operational stores;
        # AI backends are reached only through the separate AI audience route.
        # This is routing separation, not access control: the route contract
        # adds no authentication to a listener.
        otlp.signals = [ "logs" ];
        pipelines = {
          traces = [ "victoriatraces" ];
          metrics = [ "victoriametrics" ];
          logs = [ "victorialogs" ];
        };

        # Each credential lives in the secret file of the backend that owns it:
        # Langfuse's Basic header is the pair its first-run init seeds
        # (langfuse.yaml, otel/basic); Latitude's Bearer key is the UI-issued
        # project key (telemetry.yaml, latitude/api_key).
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

        # The fleet ships its whole journal to the log store: the store is ours,
        # the sink is a tailnet loopback dial, and no LLM-observability backend
        # sees log data. The contract refuses an empty allowlist without this
        # explicit licence, so the choice is stated rather than implied.
        journald = {
          enable = true;
          includeAll = true;
          sink.endpoint = "${catalog."victorialogs".endpoint.url}/insert/jsonline";
        };
      };
    };

  # Signal lanes: a lane is the whole opt-in for its signal, so a host's aspect
  # list reads as the signals it ships. These bind our names over upstream's
  # lanes — no fleet convention is left to add, exactly as `node-exporter` does.
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
