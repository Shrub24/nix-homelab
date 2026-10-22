top: {
  flake.modules.nixos.web-policy =
    {
      lib,
      config,
      ...
    }:
    let
      policyLib = import ../../lib/policy.nix { inherit lib; };

      # The policy file is plain data: the canonical cross-fleet service records
      # are nix-fleet's, threaded in rather than restated here.
      webServicesPolicy = import ../../policy/web-services.nix {
        canonicalServices = top.inputs.nix-fleet.lib.serviceEndpoints.canonicalServices;
      };

      # Host keys and every `origin.provider` must name a declared canonical host ID;
      # dial addresses never appear here. Unknown or missing placements fail closed.
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

      # Required on every route: a default would be one no consumer distinguishes. A
      # served route keeps its socket on loopback, so per-route TLS overrides are refused.
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
          # An apex redirect is answered by the edge, so it carries no origin; it is
          # the only route shape allowed to omit one.
          isRedirect = svc ? redirectTo;
          subdomain = svc.subdomain or null;
          hasTlsOverride =
            (svc.upstreamTlsServerName or null) != null
            || (svc.upstreamTlsInsecure or false)
            || (svc.upstreamTlsCaCertFile or null) != null;
        }) (policyHosts.${hostName}.services or { })
      ) (builtins.attrNames policyHosts);

      # A redirect answers the apex itself, so it must not also name a subdomain: a
      # labelled redirect would render a site the zone-level record cannot reach.
      redirectViolations = lib.concatMap (
        route:
        lib.optional (route.isRedirect && route.subdomain != null)
          "web-policy: route '${route.where}' declares redirectTo with a subdomain; a redirect is the apex only"
      ) routeExposures;

      exposureViolations = lib.concatMap (
        route:
        lib.optional (route.exposureMode == null)
          "web-policy: route '${route.where}' must declare exposureMode (allowed: ${lib.concatStringsSep ", " allowedExposureModes})"
        ++
          lib.optional
            (route.exposureMode != null && !(builtins.elem route.exposureMode allowedExposureModes))
            "web-policy: route '${route.where}' declares unknown exposureMode '${route.exposureMode}' (allowed: ${lib.concatStringsSep ", " allowedExposureModes})"
        ++ lib.optional (
          route.originProvider == null && !route.isRedirect
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
                lib.throwIf (exposureViolations ++ redirectViolations != [ ]) (lib.concatStringsSep "; " (
                  exposureViolations ++ redirectViolations
                )) webServicesPolicy
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
