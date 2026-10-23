# Shared ClickHouse substrate: the server the observability backends keep their
# traces in. Selecting the aspect enables it, so ownership is a host decision
# rather than a property of whichever consumer arrived first.
#
# No consumer registry: ClickHouse merges every file in `users.d/` at startup,
# so a consumer contributes `environment.etc."clickhouse-server/users.d/3xx-<name>.xml"`
# (its user, its network scope, its own `include_from`) and this module never
# learns that consumer exists. That is the whole difference from the PostgreSQL
# mechanism, which needs a registry because the server must provision each
# consumer's database, role, ACL and dump.
{ ... }:
{
  flake.modules.nixos.clickhouse =
    {
      config,
      pkgs,
      ...
    }:
    let
      globals = import ../../policy/globals.nix;
      serviceNetwork = globals.serviceNetwork;

      loopback = "127.0.0.1";
      serviceAddress = serviceNetwork.address;
      # Fleet policy, not a literal: Home Assistant owns 8123 on home-forge.
      httpPort = globals.observability.clickhouseHttpPort;
    in
    {
      config = {
        services.clickhouse = {
          enable = true;
          # Substitutes from the shared baseline; the dedicated pin was retired.
          package = pkgs.clickhouse;
          serverConfig = {
            listen_host = [
              loopback
              serviceAddress
            ];
            http_port = httpPort;
            tcp_port = 9000;
          };
        };

        # ClickHouse reads its config through a stable path, so a serverConfig
        # change leaves the unit identical and would never reach the server.
        systemd.services.clickhouse.restartTriggers = [
          config.environment.etc."clickhouse-server/config.d/100-nixos-module-config.yaml".source
        ];

        systemd.services.clickhouse.serviceConfig = {
          # sops-install-secrets can leave /run/secrets/rendered untraversable
          # for ClickHouse, which is the only non-root reader here. NixOS has no
          # /bin, so the store path; `-` because no consumer may have rendered a
          # template yet.
          ExecStartPre = "-+${pkgs.coreutils}/bin/chmod 0755 /run/secrets/rendered";
          # svc0 appears only after networkd applies it, which no unit ordering
          # expresses; retry the start.
          Restart = "on-failure";
          RestartSec = 5;
        };
      };
    };
}
