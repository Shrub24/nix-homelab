# Kanidm's OIDC client projection: its endpoint and scope conventions. Value-imported
# by the intrinsic contract, so it deploys nothing.
{ providerUrl }:
let
  openidBase = clientId: "${providerUrl}/oauth2/openid/${clientId}";
in
{
  providerName = "Kanidm";

  # `groups_name` yields bare group names in the `groups` claim.
  groupsClaim = "groups";
  nativeScope = scope: if scope == "groups" then "groups_name" else scope;

  endpoints = clientId: {
    issuerUrl = openidBase clientId;
    wellknownUrl = "${openidBase clientId}/.well-known/openid-configuration";
    authorizationUrl = "${providerUrl}/ui/oauth2";
    tokenUrl = "${providerUrl}/oauth2/token";
    userinfoUrl = "${openidBase clientId}/userinfo";
    jwksUrl = "${openidBase clientId}/public_key.jwk";
  };
}
