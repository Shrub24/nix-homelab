{ lib, config, ... }:
let
  hostName = config.networking.hostName;
in
{
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
  };
}
