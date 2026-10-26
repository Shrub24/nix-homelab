# Authentik's OIDC client projection. Every application is its own provider, so the
# client id doubles as the application slug in the issuer path.
{ providerUrl }:
let
  issuer = slug: "${providerUrl}/application/o/${slug}/";
in
{
  providerName = "Authentik";

  # The generated `groups` scope mapping releases group names under this claim.
  groupsClaim = "groups";

  endpoints = slug: {
    issuerUrl = issuer slug;
    wellknownUrl = "${issuer slug}.well-known/openid-configuration";
    authorizationUrl = "${providerUrl}/application/o/authorize/";
    tokenUrl = "${providerUrl}/application/o/token/";
    userinfoUrl = "${providerUrl}/application/o/userinfo/";
    jwksUrl = "${issuer slug}jwks/";
  };
}
