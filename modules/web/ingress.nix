# Ingress deployment aspect: selecting it supplies `services.ingress.enable`, so
# no host repeats the top-level enablement. This contributor keeps the edge-role
# projection from canonical web policy — routes, primary domain, ACME identity,
# and Authenticated Origin Pulls derive from `policy/web-services.nix` and the
# repo CA certificate. The read is one-way and guarded so an origin host renders
# no routes and a non-web host cannot force policy values.
_: {
  flake.modules.nixos.ingress =
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.services.ingress;
      currentHost = lib.attrByPath [ "repo" "web" "currentHost" ] { } config;
      resolvedRoutes = currentHost.services or { };
      primaryDomain = currentHost.primaryDomain or "";

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

      isEdge = cfg.role == "edge";
    in
    {
      services.ingress = lib.mkMerge [
        { enable = true; }

        (lib.mkIf isEdge {
          inherit primaryDomain;
          acmeEmail = "infra@${primaryDomain}";
          authenticatedOriginPulls = {
            enable = true;
            caCertFile = toString ../../certs/authenticated_origin_pull_ca.pem;
          };
          routes = edgeRoutes;
        })
      ];
    };
}
