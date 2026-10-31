# Encrypted credential sources read by the identity providers: each client's existing
# file (paths encode SOPS readership, so a provider swap must not restate them) and
# Authentik's own runtime credentials. Client keys are `<client>/client_secret`.
{
  # Authentik's own runtime credentials: the file whose presence enables the provider.
  authentik = ../../secrets/identity/authentik.yaml;

  clients = {
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
}
