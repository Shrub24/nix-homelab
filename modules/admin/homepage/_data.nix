{
  config,
  policyServices,
  ...
}:
let
  # `href` is the published URL (the browser reaches it through the edge);
  # widget APIs are internal, so the dashboard declares its own targets from
  # the fleet's single tailnet-suffix authority.
  requireRoute = name: policyServices.${name};
  serviceHref = name: (requireRoute name).publicUrl;
  globals = import ../../../policy/globals.nix;
  internalUrl = hostId: port: "http://${hostId}.${globals.tailnet.suffix}:${toString port}";
in
{
  settings = {
    title = "Shrublab Admin";
    headerStyle = "boxedWidgets";
    startUrl = "${serviceHref "admin-homepage"}#overview";
    layout = {
      Glance = {
        tab = "Overview";
        style = "row";
        columns = 3;
        icon = "mdi-view-dashboard";
        useEqualHeights = true;
      };
      Access = {
        tab = "Access";
        style = "row";
        columns = 4;
        icon = "mdi-link-variant";
      };
      "0Links" = {
        style = "row";
        columns = 4;
        iconsOnly = true;
        header = false;
        icon = "mdi-bookmark-multiple";
      };
    };
  };

  widgets = [
    {
      resources = {
        cpu = true;
        memory = true;
        disk = "/";
      };
    }
  ];

  services = [
    {
      Glance = [
        {
          "Beszel Hub" = {
            icon = "beszel";
            description = "Fleet visibility and metrics";
            href = serviceHref "beszel-admin";
            widget = {
              type = "beszel";
              url = internalUrl "la-admin-1" 8090;
              username = "{{HOMEPAGE_VAR_BESZEL_USER}}";
              password = "{{HOMEPAGE_VAR_BESZEL_PASSWORD}}";
              version = 2;
            };
          };
        }
        {
          Caddy = {
            icon = "caddy";
            description = "Edge proxy runtime";
            href = serviceHref "admin-homepage";
            widget = {
              # Explicit local-only no-auth exception (loopback admin API).
              type = "caddy";
              url = "http://127.0.0.1:2019";
            };
          };
        }
        {
          Tailscale = {
            icon = "tailscale";
            description = "Tailnet connectivity and node state";
            href = "https://login.tailscale.com/admin/machines";
            widget = {
              type = "tailscale";
              deviceid = "{{HOMEPAGE_VAR_TAILSCALE_DEVICEID}}";
              key = "{{HOMEPAGE_VAR_TAILSCALE_API_KEY}}";
            };
          };
        }
        {
          Gatus = {
            icon = "gatus";
            description = "Health checks and status";
            href = serviceHref "gatus-admin";
            widget = {
              type = "gatus";
              url = internalUrl "la-admin-1" 8087;
            };
          };
        }
        {
          Navidrome = {
            icon = "navidrome";
            description = "Music streaming status";
            href = serviceHref "navidrome";
            widget = {
              type = "navidrome";
              url = internalUrl "home-forge" 4533;
              user = "{{HOMEPAGE_VAR_NAVIDROME_USER}}";
              token = "{{HOMEPAGE_VAR_NAVIDROME_TOKEN}}";
              salt = "{{HOMEPAGE_VAR_NAVIDROME_SALT}}";
            };
          };
        }
        {
          Slskd = {
            icon = "slskd";
            description = "Soulseek queue and transfer status";
            href = serviceHref "slskd";
            widget = {
              type = "slskd";
              url = internalUrl "home-forge" 5030;
              key = "{{HOMEPAGE_VAR_SLSKD_KEY}}";
            };
          };
        }
        {
          Tagr = {
            icon = "mdi-tag-multiple";
            description = "Manual metadata and artwork fallback";
            href = serviceHref "tagr";
            siteMonitor = serviceHref "tagr";
          };
        }
      ];
    }
    {
      Access = [
        {
          "Cockpit (OCI)" = {
            icon = "mdi-console-network";
            description = "oci-melb-1 server administration";
            href = serviceHref "cockpit-oci-melb-1";
            siteMonitor = serviceHref "cockpit-oci-melb-1";
          };
        }
        {
          Termix = {
            icon = "mdi-console";
            description = "Interactive admin shell";
            href = serviceHref "termix-admin";
            siteMonitor = serviceHref "termix-admin";
          };
        }
        {
          Vaultwarden = {
            icon = "vaultwarden";
            description = "Password vault";
            href = serviceHref "vaultwarden-admin";
            siteMonitor = serviceHref "vaultwarden-admin";
          };
        }
        {
          Ntfy = {
            icon = "mdi-bell-outline";
            description = "Notification broker";
            href = serviceHref "ntfy-admin";
            siteMonitor = serviceHref "ntfy-admin";
          };
        }
        {
          Syncthing = {
            icon = "syncthing";
            description = "Cross-host file sync controller";
            href = serviceHref "syncthing-oci-melb-1";
            siteMonitor = serviceHref "syncthing-oci-melb-1";
          };
        }
      ];
    }
  ];

  bookmarks = [
    {
      "0Links" = [
        {
          "Admin Dashboard" = [
            {
              icon = "si-homeassistant";
              href = serviceHref "admin-homepage";
              description = "";
            }
          ];
        }
        {
          Tailscale = [
            {
              icon = "si-tailscale";
              href = "https://login.tailscale.com/admin/machines";
              description = "";
            }
          ];
        }
        {
          Oracle = [
            {
              icon = "si-oracle";
              href = "https://www.oracle.com/anz/cloud/sign-in.html";
              description = "";
            }
          ];
        }
        {
          Homelab = [
            {
              icon = "si-github";
              href = "https://github.com/Shrub24/nix-homelab";
              description = "";
            }
          ];
        }
      ];
    }
  ];
}
