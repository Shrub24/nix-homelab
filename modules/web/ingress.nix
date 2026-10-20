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
      ingressRoutes = import ./_ingress-routes.nix { inherit lib; };
      currentHost = lib.attrByPath [ "repo" "web" "currentHost" ] { } config;
      # `publish = false` is a posture, not progress: the route keeps its
      # identity — public URL, OIDC callback, origin and access posture — while
      # the edge serves nothing for it. A route is published unless the policy
      # says otherwise, because declaring a route at all is the publication
      # declaration; withholding is the exception and has to be written down.
      resolvedRoutes = lib.filterAttrs (name: svc: svc.publish or true) (currentHost.services or { });
      primaryDomain = currentHost.primaryDomain or "";

      edgeRoutes = ingressRoutes resolvedRoutes;

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
