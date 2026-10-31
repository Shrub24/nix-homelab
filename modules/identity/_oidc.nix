# Intrinsic OIDC client contract: approved clients projected through the active
# provider's conventions. Deploys and registers nothing, so readers import it.
{ lib, config, ... }:
let
  policy = import ../../policy/identity.nix;
  projections = {
    authentik = import ./authentik/_client.nix;
  };
  projectionFor =
    provider:
    projections.${provider}
      or (throw "services.identity.oidc: unknown identity provider '${provider}' in policy/identity.nix");
  routeKey = policy.providers.${policy.provider}.route or null;
  catalogEntry =
    if routeKey == null then
      null
    else
      lib.attrByPath [
        "repo"
        "web"
        "catalog"
        routeKey
      ] null config;
  # A private route resolves no public identity; the assertion below reports it.
  derivedProviderUrl = if catalogEntry == null then null else catalogEntry.publicUrl or null;

  cfg = config.services.identity.oidc;
  # Conventions apply to the resolved identity, so a projection never decides placement.
  provider = projectionFor policy.provider { providerUrl = cfg.providerUrl; };

  declaredGroups = policy.groups;
  enabledClients = lib.filterAttrs (_name: client: client.enable or true) policy.clients;

  mkClient =
    name: clientPolicy:
    let
      scopes = lib.unique (
        map (provider.nativeScope or (scope: scope)) (
          builtins.concatLists (builtins.attrValues clientPolicy.access)
        )
      );
    in
    provider.endpoints name
    // {
      clientId = name;
      inherit scopes;
      inherit (provider) providerName groupsClaim;
    };

  # A group typo would silently void that client's access, so it fails by name.
  undeclaredGroups = lib.concatMap (
    name:
    let
      unknown = lib.subtractLists declaredGroups (builtins.attrNames enabledClients.${name}.access);
    in
    lib.optional (
      unknown != [ ]
    ) "client '${name}' grants undeclared groups: ${lib.concatStringsSep ", " unknown}"
  ) (builtins.attrNames enabledClients);
in
{
  options.services.identity.oidc = {
    providerUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = derivedProviderUrl;
      defaultText = lib.literalExpression "config.repo.web.catalog.<active provider route>.publicUrl";
      description = ''
        Canonical public URL of the active identity provider. Defaults to the
        policy-approved route for that provider; set it only to probe a
        candidate identity that has no published route yet.
      '';
    };

    clients = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      description = "Resolved OIDC client facts keyed by consumer name.";
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.providerUrl != null;
        message = "services.identity.oidc: policy/identity.nix selects provider '${policy.provider}', whose route '${toString routeKey}' declares no public identity; publish it in policy/web-services.nix or supply services.identity.oidc.providerUrl.";
      }
      {
        assertion = undeclaredGroups == [ ];
        message = "services.identity.oidc: ${lib.concatStringsSep "; " undeclaredGroups}";
      }
    ];

    services.identity.oidc.clients =
      if cfg.providerUrl == null then { } else lib.mapAttrs mkClient enabledClients;
  };
}
