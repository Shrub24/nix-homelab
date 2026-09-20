{ lib, ... }:
{
  # This host publishes Cockpit behind the LA edge, so the public host and URL
  # root are forced away from the leaf defaults.
  services.admin.cockpit = {
    publicHost = lib.mkForce "cockpit.shrublab.xyz";
    urlRoot = lib.mkForce "/oci-melb-1";
  };
}
