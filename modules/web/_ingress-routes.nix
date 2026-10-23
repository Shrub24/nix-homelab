# Project a resolved service record onto the ingress route shape. The edge and the
# tests share it, so the release path and the proof of it cannot drift.
{ lib }:
routes:
lib.mapAttrs (_: svc: {
  inherit (svc)
    subdomain
    path
    exposureMode
    category
    stripPrefix
    declarePublic
    responseHeaders
    ;
  upstream = svc.upstream or null;
  redirectTo = svc.redirectTo or null;
  deniedPaths = svc.deniedPaths or [ ];
  forceTrailingSlash = svc.forceTrailingSlash or false;
  upstreamHostHeader = svc.upstreamHostHeader or "{host}";
  upstreamTlsInsecure = svc.upstreamTlsInsecure or false;
  upstreamTlsCaCertFile = svc.upstreamTlsCaCertFile or null;
  upstreamTlsServerName = svc.upstreamTlsServerName or null;
  cloudflareAccessRequired = svc.access.requireCloudflareAccess;
  authenticatedOriginPullsRequired = svc.cloudflare.authenticatedOriginPulls;
}) routes
