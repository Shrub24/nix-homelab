# Kanidm provider: server and provisioning composition plus the identity and OIDC secret
# sources. It reads the OIDC contract but never writes it, and needs no client aspect.
_: {
  flake.modules.nixos.identity-provider =
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.services.identity.kanidm;
      kanidmRoute = config.repo.web.catalog."kanidm-admin" or null;
      providerPublicUrl =
        if kanidmRoute == null then
          throw "identity-provider: required canonical web-policy route 'repo.web.catalog.\"kanidm-admin\"' is missing for host '${
            config.networking.hostName or "?"
          }'; select the host's web policy with a kanidm-admin route"
        else
          kanidmRoute.publicUrl;
    in
    {

      config = lib.mkMerge [
        { services.identity.kanidm.enable = true; }

        (lib.mkIf cfg.enable {
          # The private front the edge dials listens on the published route port,
          # so a bind that drifts from policy would break identity silently.
          assertions = [
            {
              assertion = lib.hasSuffix ":${toString kanidmRoute.upstreamPort}" cfg.bindAddress;
              message = "identity-provider: bind address '${cfg.bindAddress}' must listen on the published route port '${toString kanidmRoute.upstreamPort}' declared by repo.web.catalog.\"kanidm-admin\"";
            }
          ];

          services.identity.kanidm = {
            appUrl = providerPublicUrl;

            secretFiles = {
              identity = ../../secrets/identity/kanidm.yaml;
              provisioning = ../../secrets/identity/provisioning.json;
              # Paths stay explicit because they encode SOPS readership; the leaf asserts the
              # key set.
              oauth2Clients = {
                beszel = ../../secrets/hosts/la-admin-1/oidc.yaml;
                termix = ../../secrets/hosts/la-admin-1/oidc.yaml;
                karakeep = ../../secrets/hosts/oci-melb-1/oidc.yaml;
                paperless = ../../secrets/hosts/oci-melb-1/oidc.yaml;
                actual = ../../secrets/hosts/oci-melb-1/oidc.yaml;
                memos = ../../secrets/hosts/oci-melb-1/oidc.yaml;
                tududi = ../../secrets/hosts/oci-melb-1/oidc.yaml;
                geopulse = ../../secrets/hosts/oci-melb-1/oidc.yaml;
                homarr = ../../secrets/hosts/oci-melb-1/oidc.yaml;
                bookorbit = ../../secrets/hosts/home-forge/oidc.yaml;
                langfuse = ../../secrets/hosts/home-forge/oidc.yaml;
                grafana = ../../secrets/hosts/home-forge/oidc.yaml;
                cloudflare-access = ../../secrets/opentofu/oidc.yaml;
              };
            };
          };
        })
      ];
    };
}
