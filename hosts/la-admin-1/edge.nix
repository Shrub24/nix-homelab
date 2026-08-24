{ config, lib, ... }:
let
  resolvedRoutes = config.repo.web.currentHost.services;
  edgeRoutes = lib.mapAttrs (_: svc: {
    inherit (svc)
      subdomain
      path
      exposureMode
      category
      stripPrefix
      declarePublic
      responseHeaders
      upstream
      ;
    forceTrailingSlash = svc.forceTrailingSlash or false;
    upstreamHostHeader = svc.upstreamHostHeader or "{host}";
    upstreamTlsInsecure = svc.upstreamTlsInsecure or false;
    upstreamTlsCaCertFile = svc.upstreamTlsCaCertFile or null;
    upstreamTlsServerName = svc.upstreamTlsServerName or null;
    cloudflareAccessRequired = svc.access.requireCloudflareAccess;
    authenticatedOriginPullsRequired = svc.cloudflare.authenticatedOriginPulls;
  }) resolvedRoutes;
in
{
  applications."edge-ingress" = {
    enable = true;
    role = "edge";
    primaryDomain = config.repo.web.currentHost.primaryDomain;
    acmeEmail = "infra@${config.repo.web.currentHost.primaryDomain}";
    authenticatedOriginPulls = {
      enable = true;
      caCertFile = toString ../../certs/authenticated_origin_pull_ca.pem;
    };
    routes = edgeRoutes;
  };
}
