# Identity-provider deployment aspect: owns the Kanidm server/provisioning
# composition, the Kanidm top-level enablement, and the provider's identity and
# OIDC provisioning secret sources. The provider derives its public URL from
# canonical web policy, owns its TLS material locally, and never writes the OIDC
# contract namespace (`services.identity.oidc.*` is only asserted to agree, in
# the Kanidm leaf, which imports that contract intrinsically); selecting this
# aspect does not require any client capability to be selected as well.
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
              # Provider-owned OIDC provisioning secret-source map keyed by
              # canonical oauth2 client id. Paths stay explicit — they encode
              # SOPS readership and blast radius and are never inferred from
              # logical client metadata. Missing or extra keys fail the leaf's
              # key assertions.
              oauth2Clients = {
                beszel = ../../secrets/hosts/la-admin-1/oidc.yaml;
                termix = ../../secrets/hosts/la-admin-1/oidc.yaml;
                karakeep = ../../secrets/hosts/oci-melb-1/oidc.yaml;
                paperless = ../../secrets/hosts/oci-melb-1/oidc.yaml;
                cloudflare-access = ../../secrets/opentofu/oidc.yaml;
              };
            };
          };
        })
      ];
    };
}
