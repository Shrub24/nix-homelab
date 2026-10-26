# Termix: selection imports the leaf and owns the shared composition (OIDC wiring, backup
# registration, Tailscale serve). It consumes only public contracts.
_: {
  flake.modules.nixos.termix =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.services.admin.termix;
      oauth2Policy = (import ../../policy/identity.nix).clients;
      policyServices = config.repo.web.catalog or { };
      termixRoute = policyServices.${oauth2Policy.termix.route} or null;
      termixUpstream = "127.0.0.1:8083"; # container publishes 8083 (see termix-runtime.nix)
      termixClient =
        let
          client = lib.attrByPath [ "services" "identity" "oidc" "clients" "termix" ] null config;
        in
        if client == null then
          throw "termix: required OIDC contract 'services.identity.oidc.clients.termix' is missing for host '${
            config.networking.hostName or "?"
          }'; approve it in policy/identity.nix"
        else
          client;
      oidcRuntimeEnabled =
        if !(oauth2Policy.termix ? route) || termixRoute == null then
          true
        else
          termixRoute.access.oidc.enabled or true;
    in
    {
      imports = [
        ../backups/state-backups/_consumer.nix
        # The contract is a library its readers compose, so a host that runs Termix resolves
        # the client without selecting any identity provider.
        ../identity/_oidc.nix
      ];

      config = lib.mkMerge [

        {

          services.admin.termix.oidc = {
            enabled = oidcRuntimeEnabled;
            inherit (termixClient) clientId providerName;
            inherit (termixClient) issuerUrl;
            inherit (termixClient) authorizationUrl;
            inherit (termixClient) tokenUrl;
            inherit (termixClient) userinfoUrl;
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
            # Start limits are [Unit] settings; systemd ignores them in [Service].
            unitConfig = {
              StartLimitIntervalSec = 300;
              StartLimitBurst = 3;
            };
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              # Recover if tailscaled is slow to reach Running; stop after 3 tries so a genuinely
              # logged-out node fails loudly instead of spinning.
              Restart = "on-failure";
              RestartSec = "10s";
              ExecStart = ''
                ${pkgs.tailscale}/bin/tailscale serve --yes --bg --https=8443 ${termixUpstream}
              '';
              ExecStop = ''
                ${pkgs.tailscale}/bin/tailscale serve --https=8443 off
              '';
            };
          };
        }
      ];
    };
}
