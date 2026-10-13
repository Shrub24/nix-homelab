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
      # A policy route that declares publicReady=false has an identity but no
      # publication yet: the edge serves nothing for it until the policy says the
      # route is ready, so a declared public origin never answers on its own.
      resolvedRoutes = lib.filterAttrs (name: svc: svc.publicReady or true) (currentHost.services or { });
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
