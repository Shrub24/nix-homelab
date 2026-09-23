# Origin-role sibling of the `ingress` aspect: a host that provides a route
# exposed through a provider front (`exposureMode = "tailscale-serve"`) renders
# the front the edge dials, because that route's socket stays on loopback. Every
# mechanism-specific detail lives in this one file, so a service module never
# learns how the private network exposes it and the mechanism can be replaced
# without touching policy, hosts, or services.
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

      # The front terminates the private network's own TLS and dials the
      # service's loopback socket on the same port. Nothing validates that
      # inner pair: its security boundary is localhost, not PKI.
      backend = svc: "${svc.scheme}+insecure://127.0.0.1:${routePort svc}";

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
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            # Recover if the daemon is slow to reach Running; stop after three
            # tries so a logged-out node fails loudly instead of spinning.
            Restart = "on-failure";
            RestartSec = "10s";
            StartLimitIntervalSec = 300;
            StartLimitBurst = 3;
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
