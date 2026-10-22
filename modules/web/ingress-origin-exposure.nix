# The front a provider host renders for its own `tailscale-serve` routes, whose socket
# stays on loopback. Every mechanism-specific detail lives here, so no service learns it.
_: {
  flake.modules.nixos.ingress =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.services.ingress;
      provided = lib.filterAttrs (_: svc: svc.exposureMode == "tailscale-serve") (
        lib.attrByPath [ "repo" "web" "originServices" ] { } config
      );

      routePort = svc: toString svc.port;

      # The front terminates TLS and dials the loopback socket on the same port. An https
      # origin is not validated: the boundary is localhost. `serve` has no http+insecure.
      backend =
        svc:
        "${if svc.scheme == "https" then "https+insecure" else svc.scheme}://127.0.0.1:${routePort svc}";

      mkFront =
        name: svc:
        lib.nameValuePair "tailscale-serve-${name}" {
          description = "Expose ${name} to the edge over the private network";
          requires = [ "tailscaled.service" ];
          wants = [ "tailscaled-autoconnect.service" ];
          after = [
            "tailscaled-autoconnect.service"
            "tailscaled.service"
          ];
          partOf = [ "tailscaled.service" ];
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
            # Recover if the daemon is slow to reach Running; stop after three
            # tries so a logged-out node fails loudly instead of spinning.
            Restart = "on-failure";
            RestartSec = "10s";
            ExecStart = "${pkgs.tailscale}/bin/tailscale serve --yes --bg --https=${routePort svc} ${backend svc}";
            ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=${routePort svc} off";
          };
        };
    in
    {
      config = lib.mkIf (cfg.enable && provided != { }) {
        systemd.services = lib.mapAttrs' mkFront provided;
      };
    };
}
