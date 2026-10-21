{ lib }:
let
  # Single tailnet suffix authority (policy/globals.nix), used only to turn a
  # placement ID into a dialable tailnet name.
  tailnetSuffix = (import ../policy/globals.nix).tailnet.suffix;

  # Ingress upstream transport — mode-driven: `direct` is the edge-local
  # loopback exception, and every other mode names a tailnet-bound socket
  # (the origin's own socket or a `tailscale-serve` front), so it is dialed
  # by provider FQDN even when provider and edge coincide. Identity (public
  # URLs, OIDC endpoints, TLS server names) never derives through here; it
  # stays literal and stable in the policy.
  upstreamHost =
    provider: exposureMode: dialer:
    if exposureMode == "direct" && provider == dialer then
      "127.0.0.1"
    else
      "${provider}.${tailnetSuffix}";

  # Machine-to-machine endpoint transport — locality-driven, the service-to-
  # service counterpart the ingress policy does not subsume: a private service
  # colocated with the host evaluating this projection is reached over
  # loopback (unless it is served through a tailnet front), otherwise by
  # provider FQDN. A provider move stays a placement edit in the policy; no
  # consumer changes.
  endpointHost =
    provider: exposureMode: consumer:
    if exposureMode != "tailscale-serve" && provider == consumer then
      "127.0.0.1"
    else
      "${provider}.${tailnetSuffix}";
in
rec {
  hostPolicy =
    policy: hostName:
    policy.hosts.${hostName} or (throw "Unknown host '${hostName}' in policy/web-services.nix");

  resolvePrimaryDomain =
    policy: hostName:
    let
      host = hostPolicy policy hostName;
      defaults = policy.defaults or { };
      hostDefaults = host.defaults or { };
    in
    hostDefaults.primaryDomain or defaults.primaryDomain
      or (throw "Missing primaryDomain for host '${hostName}' in policy/web-services.nix");

  mergeDefaults =
    globalDefaults: hostDefaults: serviceCfg:
    lib.recursiveUpdate (lib.recursiveUpdate globalDefaults hostDefaults) serviceCfg;

  # A tailnet-served route's socket is behind the provider's Tailscale Serve
  # front, which terminates TLS on the declared port and proxies to the app's own
  # loopback listener. The dial therefore has to be https no matter what scheme
  # the application speaks: dialing the front with the app's `http` scheme is a
  # plain-HTTP request to a TLS listener, which the front answers 400.
  dialScheme =
    resolved: if resolved.exposureMode == "tailscale-serve" then "https" else resolved.origin.scheme;

  mkUpstream =
    dialer: resolved:
    "${dialScheme resolved}://${
      upstreamHost resolved.origin.provider resolved.exposureMode dialer
    }:${toString resolved.origin.port}";

  mkPublicHost =
    primaryDomain: resolved:
    if resolved.subdomain != null then "${resolved.subdomain}.${primaryDomain}" else primaryDomain;

  resolveHostServices =
    policy: hostName:
    let
      host = hostPolicy policy hostName;
      globalDefaults = policy.defaults or { };
      hostDefaults = host.defaults or { };
      services = host.services or { };
      primaryDomain = resolvePrimaryDomain policy hostName;

      mkPublicUrl =
        resolved:
        let
          base = "https://${mkPublicHost primaryDomain resolved}";
        in
        if resolved.path == "/" then base else "${base}${resolved.path}";

      mkHealthUrl = resolved: "${mkUpstream hostName resolved}${resolved.health.path}";
    in
    lib.mapAttrs (
      serviceName: serviceCfg:
      let
        resolved = mergeDefaults globalDefaults hostDefaults serviceCfg;
      in
      resolved
      // {
        service = serviceName;
        inherit primaryDomain;
        publicHost = mkPublicHost primaryDomain resolved;
        publicUrl = mkPublicUrl resolved;
      }
      # A redirect answers from the edge itself, so it has no socket to dial and
      # no health endpoint to probe; declaring an origin for it would be a lie
      # the upstream string would then repeat.
      // (
        if resolved ? redirectTo then
          { }
        else
          {
            upstream = mkUpstream hostName resolved;
            healthUrl = mkHealthUrl resolved;
          }
      )
    ) services;

  resolveCloudflareHosts =
    policy: hostName:
    let
      services = resolveHostServices policy hostName;
      publicServices = lib.filterAttrs (
        _: service:
        (service.declarePublic or false)
        && (service.exposureMode or "") != "tailscale-only"
        && (service.subdomain or "") != ""
      ) services;

      serviceList = lib.attrValues publicServices;
      publicHosts = lib.unique (map (service: service.publicHost) serviceList);

      servicesForHost = publicHost: lib.filter (service: service.publicHost == publicHost) serviceList;

      pickCanonicalService =
        servicesForPublicHost:
        let
          rootRoutes = lib.filter (service: service.path == "/") servicesForPublicHost;
          sorted = builtins.sort (a: b: a.service < b.service) servicesForPublicHost;
          sortedRoot = builtins.sort (a: b: a.service < b.service) rootRoutes;
        in
        if sortedRoot != [ ] then builtins.head sortedRoot else builtins.head sorted;
    in
    builtins.listToAttrs (
      map (
        publicHost:
        let
          hostServices = servicesForHost publicHost;
          canonicalService = pickCanonicalService hostServices;
          accessServices = lib.filter (service: service.access.requireCloudflareAccess or false) hostServices;
          rootAccessServices = lib.filter (service: service.path == "/") accessServices;
          canonicalAccessService =
            if rootAccessServices != [ ] then
              pickCanonicalService rootAccessServices
            else if accessServices != [ ] then
              pickCanonicalService accessServices
            else
              null;
        in
        {
          name = publicHost;
          value = {
            inherit publicHost;
            # The apex has no subdomain label; Cloudflare names it "@" and flattens
            # the CNAME, because a zone apex may not point at another name.
            apex = canonicalService.subdomain == null;
            hostname = if canonicalService.subdomain == null then "@" else canonicalService.subdomain;
            inherit (canonicalService) primaryDomain;
            proxied = canonicalService.cloudflare.proxied or true;
            declarePublic = true;
            inherit (canonicalService) exposureMode;
            routes = map (service: service.service) hostServices;
          }
          // lib.optionalAttrs (canonicalAccessService != null) {
            access = canonicalAccessService.access // {
              inherit (canonicalAccessService) service;
              inherit (canonicalAccessService) publicUrl;
              inherit (canonicalAccessService) path;
            };
          };
        }
      ) publicHosts
    );

  hostService =
    policy: hostName: serviceName:
    let
      services = resolveHostServices policy hostName;
    in
    services.${serviceName}
      or (throw "Unknown service '${serviceName}' for host '${hostName}' in policy/web-services.nix");

  exportHostPolicy =
    policy: hostName:
    let
      services = resolveHostServices policy hostName;
    in
    {
      routes = services;
      cloudflare = {
        hosts = resolveCloudflareHosts policy hostName;
      };
    };

  exportHostJson = policy: hostName: builtins.toJSON (exportHostPolicy policy hostName);

  hostPorts =
    policy: hostName:
    lib.mapAttrs (_: svc: svc.origin.port) (
      lib.filterAttrs (_: svc: !(svc ? redirectTo)) (resolveHostServices policy hostName)
    );

  # Provider-side projection: the routes a host provides, so a host serving an
  # origin can render the front the edge dials without reading the edge's route
  # table and without restating the port. Origins themselves never enter the
  # cross-host catalog; placement is matched by canonical host ID.
  providedServices =
    policy: hostId:
    let
      hosts = policy.hosts or { };
      entries = lib.concatMap (
        hostName:
        let
          hostDefaults = hosts.${hostName}.defaults or { };
        in
        lib.mapAttrsToList (serviceName: serviceCfg: {
          inherit serviceName;
          resolved = mergeDefaults (policy.defaults or { }) hostDefaults serviceCfg;
        }) (hosts.${hostName}.services or { })
      ) (builtins.attrNames hosts);

      provided = lib.filter (entry: (entry.resolved.origin.provider or null) == hostId) entries;
    in
    builtins.listToAttrs (
      map (entry: {
        name = entry.serviceName;
        value = {
          inherit (entry.resolved.origin) scheme port;
          inherit (entry.resolved) exposureMode;
        };
      }) provided
    );

  # Cross-host catalog projection. Every service carries the published upstream
  # *shape* (scheme + port) so a consumer can configure its own listen address,
  # and a machine-to-machine `endpoint` whose host resolves against the
  # evaluating host: loopback when that host serves the service, the provider's
  # tailnet name otherwise. In-fleet clients dial that endpoint, never the public
  # hostname — crossing the edge would hit the Access gate and Cloudflare's
  # browser-signature rule. A public service additionally exposes its published
  # identity (public URL/host, access, health); a private one leaves those null.
  # A provider move stays a placement edit here and never a consumer edit.
  isPublicService =
    resolved: (resolved.declarePublic or false) && resolved.exposureMode != "tailscale-only";

  mkCatalogEntry =
    evalHostName: serviceName: resolved:
    let
      public = isPublicService resolved;
      endpointHostValue = endpointHost resolved.origin.provider resolved.exposureMode evalHostName;
      endpoint =
        let
          scheme = dialScheme resolved;
        in
        {
          inherit scheme;
          host = endpointHostValue;
          port = resolved.origin.port;
          url = "${scheme}://${endpointHostValue}:${toString resolved.origin.port}";
        };
    in
    {
      service = serviceName;
      upstreamScheme = resolved.origin.scheme;
      upstreamPort = resolved.origin.port;
      publicUrl = if public then resolved.publicUrl else null;
      publicHost = if public then resolved.publicHost else null;
      publicDomain = if public then resolved.primaryDomain else null;
      inherit endpoint;
      # The route's publication posture travels with the catalog entry: it is
      # property of the route, not of the browser that reads it, and a consumer
      # that must behave differently while its route is withheld (a private
      # instance versus a published one) would otherwise have to read the
      # provider-host record. Same default as the edge filter.
      publish = resolved.publish or true;
      inherit (resolved)
        primaryDomain
        subdomain
        path
        category
        declarePublic
        exposureMode
        access
        health
        ;
    };

  serviceCatalog =
    policy: evalHostName:
    let
      hosts = policy.hosts or { };
      # A redirect route is published identity with no dial target, so it stays out
      # of the cross-host catalog: consumers resolve sockets here, not landing points.
      allServices = lib.concatLists (
        lib.mapAttrsToList (
          hostName: _:
          lib.mapAttrsToList (serviceName: resolved: {
            inherit hostName serviceName resolved;
          }) (lib.filterAttrs (_: resolved: !(resolved ? redirectTo)) (resolveHostServices policy hostName))
        ) hosts
      );

      byServiceId = builtins.groupBy (entry: entry.serviceName) allServices;

      duplicateIds = lib.filterAttrs (_: entries: builtins.length entries > 1) byServiceId;

      duplicateMessage = lib.concatStringsSep ", " (
        map (id: "${id} (${lib.concatMapStringsSep ", " (entry: entry.hostName) duplicateIds.${id}})") (
          builtins.attrNames duplicateIds
        )
      );

      checked =
        if duplicateIds == { } then
          allServices
        else
          throw "Duplicate service catalog key(s) in policy/web-services.nix: ${duplicateMessage}";
    in
    builtins.listToAttrs (
      map (entry: {
        name = entry.serviceName;
        value = mkCatalogEntry evalHostName entry.serviceName entry.resolved;
      }) checked
    );
}
