# Termix deployment aspect (dendritic Stage 7, D-053). Published from this
# discovered contributor and selected only on `la-admin-1` (S7-2, explicit
# `aspects.termix`). Selecting the aspect imports the Termix leaf and owns the
# shared Termix composition: the identity-client OIDC endpoint wiring, the
# state-backup registration, and the dedicated Tailscale serve unit. The
# runtime data path stays the leaf default (`/srv/data/termix`), the value the
# previous `applications.admin.dataRoot`-derived wiring produced.
#
# Dependency direction (decouple-identity-admin-capabilities 3.1): the aspect
# consumes only public contracts — `services.identity.oidc.clients.termix`
# (identity-client) and canonical web policy
# (`repo.web.currentHost.services."termix-admin"`) — and never reads the
# `applications.admin` namespace or the provider's Kanidm namespace. The host
# keeps only the host-scoped OIDC secret source
# (`services.admin.termix.secretFiles.oidc`).
#
# Named dependency failures (feature-topology/admin-module-structure): a
# selection without either public contract must fail through a named throw
# identifying the missing contract — the canonical web-policy route or
# `services.identity.oidc.clients.termix` — not a raw missing-option
# namespace error.
{ ... }:
{
  flake.modules.nixos.termix =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.services.admin.termix;
      oauth2Policy = (builtins.fromJSON (builtins.readFile ../../policy/identity.json)).systems.oauth2;
      policyServices = config.repo.web.currentHost.services or { };
      termixRoute = policyServices.${oauth2Policy.termix.routeKey} or null;
      # Named contract failure (same pattern as identity-provider): a host
      # selecting this aspect without the canonical web-policy route must fail
      # loudly, not with a missing-option error.
      termixUpstream =
        if termixRoute == null then
          throw "termix: required canonical web-policy route 'repo.web.currentHost.services.\"${oauth2Policy.termix.routeKey}\"' is missing for host '${
            config.networking.hostName or "?"
          }'"
        else
          termixRoute.upstream;
      # Named contract failure (decouple-identity-admin-capabilities 3.1,
      # feature-topology/admin-module-structure): a selection without the
      # identity-client contract fails through this named throw, not a raw
      # missing-option namespace error. The safe attrByPath lookup keeps the
      # guard independent of whether any sibling declared `services.identity`.
      termixClient =
        let
          client = lib.attrByPath [ "services" "identity" "oidc" "clients" "termix" ] null config;
        in
        if client == null then
          throw "termix: required identity-client contract 'services.identity.oidc.clients.termix' is missing for host '${
            config.networking.hostName or "?"
          }'; select the identity-client aspect"
        else
          client;
      # Null-aware policy read: consumes the guarded Termix web-policy route
      # (`termixRoute`, `or null`) instead of indexing policyServices by
      # route key. A missing route defaults OIDC runtime on; the named route
      # throw in `termixUpstream` fires when that wiring is consumed.
      oidcRuntimeEnabled =
        if !(oauth2Policy.termix ? routeKey) || termixRoute == null then
          true
        else
          termixRoute.access.oidc.enabled or true;
    in
    {
      imports = [ ../services/admin/termix.nix ];

      config = lib.mkMerge [
        # Selecting this aspect is the capability's top-level enablement.
        { services.admin.termix.enable = true; }

        (lib.mkIf cfg.enable {
          services.admin.termix.oidc = {
            enabled = oidcRuntimeEnabled;
            clientId = termixClient.clientId;
            issuerUrl = termixClient.issuerUrl;
            authorizationUrl = termixClient.authorizationUrl;
            tokenUrl = termixClient.tokenUrl;
            userinfoUrl = termixClient.userinfoUrl;
            environmentFile = if oidcRuntimeEnabled then config.sops.templates."termix-oidc.env".path else null;
          };

          services.state-backups.services.termix = {
            enable = true;
            mode = "live";
            paths = [ cfg.dataDir ];
          };

          systemd.services.tailscale-serve-termix = {
            description = "Expose Termix via dedicated Tailscale HTTPS port";
            requires = [
              "tailscaled.service"
              "podman-termix.service"
            ];
            wants = [ "tailscaled-autoconnect.service" ];
            after = [
              "tailscaled-autoconnect.service"
              "tailscaled.service"
              "podman-termix.service"
            ];
            partOf = [
              "tailscaled.service"
              "podman-termix.service"
            ];
            restartIfChanged = true;
            stopIfChanged = true;
            wantedBy = [ "multi-user.target" ];
            preStart = "${pkgs.tailscale}/bin/tailscale wait --timeout=60s";
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              # Recover if tailscaled is slow to reach Running; stop after 3
              # tries so a genuinely logged-out node fails loudly instead of
              # spinning.
              Restart = "on-failure";
              RestartSec = "10s";
              StartLimitIntervalSec = 300;
              StartLimitBurst = 3;
              ExecStart = ''
                ${pkgs.tailscale}/bin/tailscale serve --yes --bg --https=8443 ${termixUpstream}
              '';
              ExecStop = ''
                ${pkgs.tailscale}/bin/tailscale serve --https=8443 off
              '';
            };
          };
        })
      ];
    };
}
