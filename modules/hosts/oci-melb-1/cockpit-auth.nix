{ lib, ... }:
{
  # Cockpit composition is owned by the selected `cockpit` aspect (service
  # user, common secret registration, and Tailscale Serve enablement). This
  # host keeps only its genuine OCI variants: the policy-shaped public host and
  # URL root for a published Cockpit behind the LA edge.
  services.admin.cockpit = {
    publicHost = lib.mkForce "cockpit.shrublab.xyz";
    urlRoot = lib.mkForce "/oci-melb-1";
  };
}
