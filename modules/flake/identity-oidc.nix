{ ... }:
{
  flake.modules.nixos.identity-client =
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.services.identity.oidc;
      identityPolicy = builtins.fromJSON (builtins.readFile ../../policy/identity.json);
      oauth2Policy = identityPolicy.systems.oauth2 or { };
      enabledOauth2Clients = lib.filterAttrs (_name: client: client.enable or true) oauth2Policy;
      providerUrlMatch =
        if cfg.providerUrl == null then null else builtins.match "https://([^/]+).*" cfg.providerUrl;
      providerUrlValid = cfg.providerUrl == null || providerUrlMatch != null;
      clientPathPrefix = if cfg.providerUrl == null then null else "${cfg.providerUrl}/oauth2/openid";
      mkClientOidcEndpoints = clientId: {
        inherit clientId;
        issuerUrl = "${clientPathPrefix}/${clientId}";
        wellknownUrl = "${clientPathPrefix}/${clientId}/.well-known/openid-configuration";
        authorizationUrl = "${cfg.providerUrl}/ui/oauth2";
        tokenUrl = "${cfg.providerUrl}/oauth2/token";
        userinfoUrl = "${clientPathPrefix}/${clientId}/userinfo";
      };
    in
    {
      options.services.identity.oidc = {
        providerUrl = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Canonical public URL for the active identity provider.";
        };

        clientPathPrefix = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          readOnly = true;
          description = "Base client-specific OIDC path prefix for the active identity provider.";
        };

        tokenUrl = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          readOnly = true;
          description = "Canonical OAuth2 token endpoint for the active identity provider.";
        };

        clients = lib.mkOption {
          type = lib.types.attrs;
          readOnly = true;
          description = "Canonical per-client OIDC endpoint outputs keyed by consumer name.";
        };
      };

      config = {
        assertions = [
          {
            assertion = providerUrlValid;
            message = "services.identity.oidc.providerUrl must be null or a valid https URL.";
          }
        ];

        services.identity.oidc = {
          clientPathPrefix = if cfg.providerUrl == null then null else clientPathPrefix;
          tokenUrl = if cfg.providerUrl == null then null else "${cfg.providerUrl}/oauth2/token";
          clients =
            if cfg.providerUrl == null then
              { }
            else
              lib.mapAttrs (name: _client: mkClientOidcEndpoints name) enabledOauth2Clients;
        };
      };
    };
}
