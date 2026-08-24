{
  "common" = [
    "oci-melb-1"
    "la-admin-1"
    "home-forge"
  ];
  "applications/music" = [ "oci-melb-1" ];
  "applications/admin" = [ "la-admin-1" ];
  "applications/edge-ingress" = [ "la-admin-1" ];

  "identity/kanidm" = [ "la-admin-1" ];
  "identity/provisioning.json" = [ "la-admin-1" ];

  "services/karakeep-pod" = [ "oci-melb-1" ];
  "services/bifrost-gateway" = [ "oci-melb-1" ];
  "services/ntfy" = [ "la-admin-1" ];
  "services/ntfy-firebase-key.json" = [ "la-admin-1" ];
  "services/notification-daemon" = [
    "oci-melb-1"
    "la-admin-1"
    "home-forge"
  ];

  "opentofu/oidc" = [ "la-admin-1" ];

  "hosts/oci-melb-1/system" = [ "oci-melb-1" ];
  "hosts/la-admin-1/system" = [ "la-admin-1" ];
  "hosts/home-forge/system" = [ "home-forge" ];

  "hosts/oci-melb-1/oidc" = [
    "oci-melb-1"
    "la-admin-1"
  ];
  "hosts/la-admin-1/oidc" = [ "la-admin-1" ];
}
