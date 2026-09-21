# Termix deployment aspect: selection imports the leaf and owns the shared
# composition (OIDC endpoint wiring, state-backup registration,
# dedicated Tailscale serve unit). It consumes only public contracts — the
# canonical OIDC client record and the canonical web-policy route.
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
      termixUpstream =
        if termixRoute == null then
          throw "termix: required canonical web-policy route 'repo.web.currentHost.services.\"${oauth2Policy.termix.routeKey}\"' is missing for host '${
            config.networking.hostName or "?"
          }'"
        else
          termixRoute.upstream;
      termixClient =
        let
          client = lib.attrByPath [ "services" "identity" "oidc" "clients" "termix" ] null config;
        in
        if client == null then
          throw "termix: required OIDC contract 'services.identity.oidc.clients.termix' is missing for host '${
            config.networking.hostName or "?"
          }'; enable systems.oauth2.termix in policy/identity.json"
        else
          client;
      oidcRuntimeEnabled =
        if !(oauth2Policy.termix ? routeKey) || termixRoute == null then
          true
        else
          termixRoute.access.oidc.enabled or true;
    in
    {
      imports = [ ../backups/state-backups/_consumer.nix ];

      config = lib.mkMerge [
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
