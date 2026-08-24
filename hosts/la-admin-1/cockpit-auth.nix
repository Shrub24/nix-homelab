{ config, ... }:
{
  services.admin.cockpit.serviceUser = {
    enable = true;
    name = "cockpit-svc";
    hashedPasswordFile = config.sops.secrets.cockpit_service_user_password_hash.path;
  };

  services.admin.cockpit.tailscaleServe.enable = true;
  services.admin.cockpit.loopbackTls.enable = true;
}
