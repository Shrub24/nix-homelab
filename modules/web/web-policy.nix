top: {
  flake.modules.nixos.web-policy =
    {
      lib,
      config,
      ...
    }:
    let
      policyLib = import ../../lib/policy.nix { inherit lib; };
      webServicesPolicy = import ../../policy/web-services.nix;

      # Every host-backed reference in the web data — the policy host keys and
      # each route's `origin.provider` placement — must name a declared
      # canonical host ID; dial addresses never appear in this file. Unknown
      # or missing placements fail closed at flake evaluation.
      canonicalHosts = top.config.nixos.hosts;
      canonicalHostIds = builtins.attrNames canonicalHosts;
      policyHosts = webServicesPolicy.hosts or { };

      unknownHostKeys = lib.filter (name: !(canonicalHosts ? ${name})) (builtins.attrNames policyHosts);

      allOrigins = lib.concatMap (
        hostName:
        let
          services = policyHosts.${hostName}.services or { };
        in
        lib.mapAttrsToList (_: svc: svc.origin.provider or null) services
      ) (builtins.attrNames policyHosts);

      unknownOrigins = lib.filter (p: p != null && !(builtins.elem p canonicalHostIds)) allOrigins;

      allowedExposureModes = [
        "direct"
        "tailscale-upstream"
        "tailscale-serve"
        "tailscale-only"
      ];

      # `exposureMode` is the single axis describing how a service is exposed,
      # so it is required on every route: an unlabelled route fails evaluation
      # instead of inheriting a default no consumer distinguishes. A served
      # route keeps its socket on loopback — the providing host renders the
      # front the edge dials and the upstream TLS name is derived from the dial
      # target — so per-route TLS overrides are refused rather than ignored.
      routeExposures = lib.concatMap (
        hostName:
        let
          hostDefaults = policyHosts.${hostName}.defaults or { };
        in
        lib.mapAttrsToList (serviceName: svc: {
          where = "${hostName}.${serviceName}";
          policyHost = hostName;
          exposureMode =
            (policyLib.mergeDefaults (webServicesPolicy.defaults or { }) hostDefaults svc).exposureMode or null;
          originProvider = svc.origin.provider or null;
          hasTlsOverride =
            (svc.upstreamTlsServerName or null) != null
            || (svc.upstreamTlsInsecure or false)
            || (svc.upstreamTlsCaCertFile or null) != null;
        }) (policyHosts.${hostName}.services or { })
      ) (builtins.attrNames policyHosts);

      exposureViolations = lib.concatMap (
        route:
        lib.optional (route.exposureMode == null)
          "web-policy: route '${route.where}' must declare exposureMode (allowed: ${lib.concatStringsSep ", " allowedExposureModes})"
        ++
          lib.optional
            (route.exposureMode != null && !(builtins.elem route.exposureMode allowedExposureModes))
            "web-policy: route '${route.where}' declares unknown exposureMode '${route.exposureMode}' (allowed: ${lib.concatStringsSep ", " allowedExposureModes})"
        ++ lib.optional (
          route.originProvider == null
        ) "web-policy: route '${route.where}' must declare origin.provider (a canonical host ID)"
        ++
          lib.optional
            (
              route.exposureMode == "direct"
              && route.originProvider != null
              && route.originProvider != route.policyHost
            )
            "web-policy: route '${route.where}' declares direct (edge-local loopback) but origin.provider '${toString route.originProvider}' is not this policy host"
        ++
          lib.optional (route.exposureMode == "tailscale-serve" && route.hasTlsOverride)
            "web-policy: route '${route.where}' is served through a provider front and must not also set an upstream TLS server name, insecure flag, or CA file"
      ) routeExposures;

      checkedPolicy =
        lib.throwIf (unknownHostKeys != [ ])
          (lib.concatMapStringsSep "; " (
            name: "web-policy: unknown host reference '${name}' is not a declared canonical host ID"
          ) unknownHostKeys)
          (
            lib.throwIf (unknownOrigins != [ ])
              (lib.concatMapStringsSep "; " (
                provider: "web-policy: origin provider '${provider}' is not a declared canonical host ID"
              ) unknownOrigins)
              (
                lib.throwIf (
                  exposureViolations != [ ]
                ) (lib.concatStringsSep "; " exposureViolations) webServicesPolicy
              )
          );

      currentHostName = config.networking.hostName or null;
      resolvedHosts = lib.mapAttrs (hostName: _host: {
        primaryDomain = policyLib.resolvePrimaryDomain checkedPolicy hostName;
        services = policyLib.resolveHostServices checkedPolicy hostName;
        cloudflare.hosts = policyLib.resolveCloudflareHosts checkedPolicy hostName;
      }) (checkedPolicy.hosts or { });

      catalog = policyLib.serviceCatalog checkedPolicy currentHostName;
    in
    {
      options.repo.web = {
        hosts = lib.mkOption {
          type = lib.types.attrs;
          readOnly = true;
          description = "Resolved web-services policy for all hosts.";
        };

        catalog = lib.mkOption {
          type = lib.types.attrs;
          readOnly = true;
          description = "Canonical cross-host service catalog keyed by stable service ID.";
        };

        currentHost = lib.mkOption {
          type = lib.types.attrs;
          readOnly = true;
          description = "Resolved web-services policy for the current host.";
        };

        originServices = lib.mkOption {
          type = lib.types.attrs;
          readOnly = true;
          description = ''
            Routes this host provides to the edge, with the transport the edge
            must use to reach them. Empty on a host that provides no route.
          '';
        };
      };

      config.repo.web = {
        hosts = resolvedHosts;
        inherit catalog;
        currentHost =
          if currentHostName != null && builtins.hasAttr currentHostName resolvedHosts then
            resolvedHosts.${currentHostName}
          else
            { };
        originServices =
          if currentHostName != null && canonicalHosts ? ${currentHostName} then
            policyLib.providedServices checkedPolicy currentHostName
          else
            { };
      };
    };
}
