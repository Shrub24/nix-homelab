{
  "common" = [
    "oci-melb-1"
    "la-admin-1"
    "home-forge"
  ];
  "applications/music" = [
    "oci-melb-1"
    "home-forge"
  ];
  "applications/admin" = [ "la-admin-1" ];
  "applications/edge-ingress" = [ "oci-melb-1" ];

  "identity/kanidm" = [ "la-admin-1" ];
  "identity/provisioning.json" = [ "la-admin-1" ];

  "services/degoog" = [ "home-forge" ];
  "services/hindsight" = [ "home-forge" ];
  "services/karakeep-pod" = [ "oci-melb-1" ];
  "services/langfuse" = [
    "oci-melb-1"
    "home-forge"
  ];
  "services/latitude" = [
    "oci-melb-1"
    "home-forge"
  ];
  "services/telemetry" = [
    "oci-melb-1"
    "home-forge"
  ];
  "services/bifrost" = [
    "oci-melb-1"
    "home-forge"
  ];
  "services/omniroute" = [ "home-forge" ];
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
  # Langfuse's client secret source for both the provider (la-admin-1) and
  # the consumer (home-forge).
  "hosts/home-forge/oidc" = [
    "home-forge"
    "la-admin-1"
  ];
}
