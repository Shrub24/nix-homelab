{ config, ... }:
{
  services.admin.cockpit = {
    serviceUser = {
      enable = true;
      name = "cockpit-svc";
      hashedPasswordFile = config.sops.secrets.cockpit_service_user_password_hash.path;
    };

    tailscaleServe.enable = true;
    loopbackTls.enable = true;
  };
}
