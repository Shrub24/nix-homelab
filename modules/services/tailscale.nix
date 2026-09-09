# Tailscale service leaf, owned by the published `tailscale` foundation aspect
# (flake.modules.nixos.tailscale imports this leaf). The leaf owns the
# conventional host-scoped auth-key registration and the nullable MTU variant
# in addition to the service wiring itself (design FND-4).
#
# - auth-key source: secrets/hosts/${config.networking.hostName}/system.yaml
#   under key tailscale/auth_key, rendered to /run/secrets/tailscale.auth_key
#   (mode 0400) and set as services.tailscale.authKeyFile. When the host scope
#   does not exist yet (two-step sops bootstrap) nothing is registered and
#   tailscaled stays unauthenticated until the operator adds the scope.
# - debugMtu: when a host declares services.tailscale.debugMtu, the leaf
#   writes TS_DEBUG_MTU into the tailscaled unit environment. OCI and LA use
#   1200; home-forge leaves it unset.
{
  lib,
  config,
  ...
}:
let
  hostName = config.networking.hostName;
  hostSystemSecret = ../../secrets/hosts + "/${hostName}/system.yaml";
  hasHostSecrets = builtins.pathExists hostSystemSecret;
  cfg = config.services.tailscale;
in
{
  options.services.tailscale.debugMtu = lib.mkOption {
    type = lib.types.nullOr lib.types.int;
    default = null;
    description = ''
      Optional Tailscale TUN MTU override. When set, the module writes
      TS_DEBUG_MTU into the tailscaled unit environment. Host-scoped packet
      size workaround only: no enrollment, identity, tag, firewall, route, or
      experimental PMTUD change (see specs/network-access/spec.md).
    '';
  };

  config = {
    systemd.services = {
      tailscaled = {
        restartIfChanged = false;
        stopIfChanged = false;
      };
      tailscaled-autoconnect = {
        restartIfChanged = false;
        stopIfChanged = false;
        wants = [ "sops-install-secrets.service" ];
        after = [ "sops-install-secrets.service" ];
      };
    };

    services.tailscale = {
      enable = true;
      openFirewall = false;
      extraSetFlags = [ "--ssh" ];
      extraUpFlags = lib.mkDefault [
        "--hostname=${hostName}"
      ];
      authKeyFile = lib.mkIf hasHostSecrets "/run/secrets/tailscale.auth_key";
    };

    sops.secrets = lib.mkIf hasHostSecrets {
      tailscale_auth_key = {
        sopsFile = hostSystemSecret;
        key = "tailscale/auth_key";
        path = "/run/secrets/tailscale.auth_key";
        mode = "0400";
      };
    };

    systemd.services.tailscaled.environment = lib.mkIf (cfg.debugMtu != null) {
      TS_DEBUG_MTU = toString cfg.debugMtu;
    };
  };
}
