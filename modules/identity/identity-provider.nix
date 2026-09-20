# Identity-provider deployment aspect (dendritic Stage 7, D-053). Published
# from this discovered contributor and selected only on `la-admin-1` (S7-2).
# It owns the Kanidm server/provisioning composition, the Kanidm top-level
# enablement, the provider data root, and the provider's identity and OIDC
# provisioning secret sources.
#
# Directional contracts (decouple-identity-admin-capabilities IDB-1/IDB-2):
#   * the provider never reads an admin workload namespace
#     (`applications.admin` is not referenced anywhere below);
#   * the provider derives its own public URL from canonical web policy
#     (`repo.web.currentHost.services."kanidm-admin".publicUrl`, the
#     `providerPublicUrl` binding below) and never reads or writes the client
#     namespace (`services.identity.oidc.*` is only asserted to agree, in the
#     Kanidm leaf), so the identity-client contract is consumed by clients,
#     not by the provider;
#   * endpoint/TLS data comes from canonical web policy
#     (`repo.web.currentHost.services."kanidm-admin"`), never from an admin
#     namespace re-export.
# A host selecting this aspect without `identity-client` fails through the
# named provider-URL assertion in the Kanidm leaf, not a missing-option error.
{ ... }:
{
  flake.modules.nixos.identity-provider =
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.services.identity.kanidm;
      kanidmRoute = config.repo.web.currentHost.services."kanidm-admin" or null;
      # Named contract failure (decouple-identity-admin-capabilities: a
      # missing required identity/web contract must fail through a named
      # assertion-style throw, not a missing-option namespace error).
      providerPublicUrl =
        if kanidmRoute == null then
          throw "identity-provider: required canonical web-policy route 'repo.web.currentHost.services.\"kanidm-admin\"' is missing for host '${
            config.networking.hostName or "?"
          }'; select the host's web policy with a kanidm-admin route"
        else
          kanidmRoute.publicUrl;
    in
    {

      config = lib.mkMerge [
        # Selecting this aspect is the Kanidm capability's top-level
        # enablement; the aspect consumes the canonical client-contract URL.
        {
          services.identity.kanidm.enable = true;
        }

        (lib.mkIf cfg.enable {
          services.identity.kanidm = {
            dataDir = "/srv/data/kanidm";
            appUrl = providerPublicUrl;
            tlsChainFile = "/var/lib/acme/${kanidmRoute.primaryDomain}/fullchain.pem";
            tlsKeyFile = "/var/lib/acme/${kanidmRoute.primaryDomain}/key.pem";
            tlsReaderGroups = [ "caddy" ];

            secretFiles = {
              identity = ../../secrets/identity/kanidm.yaml;
              provisioning = ../../secrets/identity/provisioning.json;
              # Explicit provider-owned OIDC provisioning secret-source map
              # keyed by canonical oauth2 client id (IDB-1). Paths stay
              # explicit — they encode SOPS readership and blast radius and
              # are never inferred from logical client metadata. Missing or
              # extra keys fail the leaf's key assertions.
              oauth2Clients = {
                beszel = ../../secrets/hosts/la-admin-1/oidc.yaml;
                quantum = ../../secrets/hosts/la-admin-1/oidc.yaml;
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
