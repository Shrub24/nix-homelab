# Operator development surface (perSystem): shell and formatter, carried over
# from Stage 0 unchanged except for lexical package references.
{
  perSystem =
    { pkgs, config, ... }:
    {
      devShells.default = pkgs.mkShell {
        packages =
          with pkgs;
          [
            just
            git
            jq
            yq
            opentofu
            prettier
            shfmt
            taplo
            treefmt
            sops
            age
            nixos-anywhere
            nix-output-monitor
            nixfmt
            ruff
            statix
            ssh-to-age
            lefthook
          ]
          ++ [
            config.packages.notification-daemon
            config.packages.notify
            config.packages.niks3
            config.packages.nix-path-filter
            pkgs.deploy-rs
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
