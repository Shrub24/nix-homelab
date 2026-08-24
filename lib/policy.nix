{ lib }:
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

  mkUpstream =
    resolved: "${resolved.origin.scheme}://${resolved.origin.host}:${toString resolved.origin.port}";

  mkOidcEndpoints = issuerUrl: {
    issuerUrl = issuerUrl;
    wellknownUrl = "${issuerUrl}/.well-known/openid-configuration";
    authorizationUrl = "${issuerUrl}/authorize";
    tokenUrl = "${issuerUrl}/api/oidc/token";
    userinfoUrl = "${issuerUrl}/api/oidc/userinfo";
  };

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

      mkHealthUrl = resolved: "${mkUpstream resolved}${resolved.health.path}";
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
        upstream = mkUpstream resolved;
        publicUrl = mkPublicUrl resolved;
        healthUrl = mkHealthUrl resolved;
      }
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
            hostname = canonicalService.subdomain;
            primaryDomain = canonicalService.primaryDomain;
            proxied = canonicalService.cloudflare.proxied or true;
            declarePublic = true;
            exposureMode = canonicalService.exposureMode;
            routes = map (service: service.service) hostServices;
          }
          // lib.optionalAttrs (canonicalAccessService != null) {
            access = canonicalAccessService.access // {
              service = canonicalAccessService.service;
              publicUrl = canonicalAccessService.publicUrl;
              path = canonicalAccessService.path;
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
    policy: hostName: lib.mapAttrs (_: svc: svc.origin.port) (resolveHostServices policy hostName);

  # Cross-host catalog projection: canonical public URL, access, and health
  # metadata only. Edge-local transport fields (origin, upstream, healthUrl)
  # stay out of the catalog so consumers cannot depend on a physical origin.
  mkCatalogEntry = serviceName: resolved: {
    service = serviceName;
    inherit (resolved)
      publicUrl
      publicHost
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
    policy:
    let
      hosts = policy.hosts or { };
      allServices = lib.concatLists (
        lib.mapAttrsToList (
          hostName: _:
          lib.mapAttrsToList (serviceName: resolved: {
            inherit hostName serviceName resolved;
          }) (resolveHostServices policy hostName)
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
        value = mkCatalogEntry entry.serviceName entry.resolved;
      }) checked
    );
}
