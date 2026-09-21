# Operator development surface (perSystem): shell and formatter.
{
  perSystem =
    { pkgs, config, ... }:
    {
      devShells.default = pkgs.mkShell {
        packages = [
          pkgs.just
          pkgs.git
          pkgs.jq
          pkgs.yq
          pkgs.opentofu
          pkgs.prettier
          pkgs.shfmt
          pkgs.taplo
          pkgs.treefmt
          pkgs.sops
          pkgs.age
          pkgs.nixos-anywhere
          pkgs.nix-output-monitor
          pkgs.nixfmt
          pkgs.ruff
          pkgs.statix
          pkgs.ssh-to-age
          pkgs.lefthook
          pkgs.deploy-rs
        ]
        ++ [
          config.packages.notification-daemon
          config.packages.notify
          config.packages.niks3
        ];
        shellHook = ''
          unset PYTHONPATH
          if [ -f /tmp/notification-daemon.json ]; then
            NOTIFICATION_DAEMON_CONFIG=/tmp/notification-daemon.json notification-daemon &
            DAEMON_PID=$!
            trap "kill $DAEMON_PID 2>/dev/null; echo 'notification-daemon stopped'" EXIT TERM INT
            echo "notification-daemon started (PID: $DAEMON_PID)"
          fi
        '';
      };

      formatter = pkgs.nixfmt;
    };
}
