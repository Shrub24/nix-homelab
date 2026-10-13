# Project a resolved service record onto the ingress route option shape.
#
# The edge renders one route per published service, and a test that needs to
# render a route the policy withholds has to reach the same projection: keeping
# it here means the release path and the proof of it cannot drift.
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
    upstream
    ;
  deniedPaths = svc.deniedPaths or [ ];
  forceTrailingSlash = svc.forceTrailingSlash or false;
  upstreamHostHeader = svc.upstreamHostHeader or "{host}";
  upstreamTlsInsecure = svc.upstreamTlsInsecure or false;
  upstreamTlsCaCertFile = svc.upstreamTlsCaCertFile or null;
  upstreamTlsServerName = svc.upstreamTlsServerName or null;
  cloudflareAccessRequired = svc.access.requireCloudflareAccess;
  authenticatedOriginPullsRequired = svc.cloudflare.authenticatedOriginPulls;
}) routes
