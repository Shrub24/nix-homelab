{
  # Cockpit composition is owned by the selected `cockpit` aspect (service
  # user, common secret registration, and Tailscale Serve enablement). This
  # host keeps only its genuine LA variant: host-local loopback TLS material
  # for trusted local HTTPS proxying.
  services.admin.cockpit.loopbackTls.enable = true;
}
