# The dedicated Cockpit Tailscale serve unit; a sibling file of the same aspect.
_: {
  flake.modules.nixos.cockpit =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.services.admin.cockpit;
      inherit (cfg) tailscaleServe;
      localUrl = "http://127.0.0.1:${toString config.services.cockpit.port}";
    in
    {
      config = lib.mkIf (cfg.enable && tailscaleServe.enable) {
        systemd.services.tailscale-serve-cockpit = {
          description = "Expose Cockpit via dedicated Tailscale HTTPS port";
          requires = [
            "tailscaled.service"
            "cockpit.socket"
          ];
          wants = [
            "tailscaled.service"
            "cockpit.socket"
          ];
          after = [
            "tailscaled.service"
            "cockpit.socket"
          ];
          partOf = [
            "tailscaled.service"
            "cockpit.socket"
          ];
          wantedBy = [ "multi-user.target" ];
          restartIfChanged = true;
          stopIfChanged = true;
          preStart = "${pkgs.tailscale}/bin/tailscale wait --timeout=60s";

          # Start limits are [Unit] settings; systemd ignores them in [Service].
          unitConfig = {
            StartLimitIntervalSec = 300;
            StartLimitBurst = 3;
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            # Recover if tailscaled is slow to reach Running; stop after 3 tries
            # so a genuinely logged-out node fails loudly instead of spinning.
            Restart = "on-failure";
            RestartSec = "10s";
            ExecStart = ''
              ${pkgs.tailscale}/bin/tailscale serve --yes --bg --https=${toString tailscaleServe.port} ${localUrl}
            '';
            ExecStop = ''
              ${pkgs.tailscale}/bin/tailscale serve --https=${toString tailscaleServe.port} off
            '';
          };
        };
      };
    };
}
