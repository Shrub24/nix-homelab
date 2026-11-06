# Edge-role projection from web policy: routes, primary domain, ACME identity and
# Authenticated Origin Pulls. The read is guarded, so an origin host renders no routes.
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
      resolvedRoutes = lib.filterAttrs (_: svc: svc.published or true) (currentHost.services or { });
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
          staticPages = lib.optionalAttrs (edgeRoutes ? apex) {
            apex."/privacy" = ./_pages/privacy.html;
          };
        })
      ];
    };
}
