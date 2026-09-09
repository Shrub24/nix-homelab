{ config, lib, ... }:
{
  services.admin.cockpit = {
    serviceUser = {
      enable = true;
      name = "cockpit-svc";
      denySsh = true;
      hashedPasswordFile = config.sops.secrets.cockpit_service_user_password_hash.path;
    };

    publicHost = lib.mkForce "cockpit.shrublab.xyz";
    urlRoot = lib.mkForce "/oci-melb-1";
    tailscaleServe.enable = true;
  };
}
