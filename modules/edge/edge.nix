# Edge deployment aspect (dendritic Stage 7, D-053). Published from this
# discovered contributor and selected by both the OCI private origin and the LA
# edge host; the explicit role stays a host variant (S7-2). Selecting the
# aspect supplies `applications."edge-ingress".enable`, so no host repeats the
# top-level enable.
#
# The edge-role projection from canonical web policy (S7-7) lives here because
# it is pure projection of the selected capability: routes, primary domain,
# ACME identity, and Authenticated Origin Pulls are derived from
# `policy/web-services.nix` and the repo CA certificate. The read stays one-way
# (web-policy is a support module, never imported) and is guarded so an origin
# host renders no routes and a non-web host cannot force policy values.
{ ... }:
{
  flake.modules.nixos.edge =
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.applications."edge-ingress";
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
      imports = [ ./_edge/edge-ingress.nix ];

      # Selecting this aspect is the capability's top-level enablement. The
      # host sets `role` and keeps the application-scoped secret binding.
      applications."edge-ingress" = lib.mkMerge [
        { enable = true; }

        # Edge-role projection only.
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
