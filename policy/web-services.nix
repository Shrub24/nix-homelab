let
  oci = "oci-melb-1.tail0fe19b.ts.net";
in
{
  defaults = {
    primaryDomain = "shrublab.xyz";
    exposureMode = "direct";
    category = "app";
    path = "/";
    declarePublic = true;
    stripPrefix = false;
    responseHeaders = { };

    access = {
      requireCloudflareAccess = true;
      oidc = {
        enabled = false;
        provider = "cloudflare-access";
      };
      policies = [ "allow_admins" ];
    };

    cloudflare = {
      proxied = true;
      authenticatedOriginPulls = true;
    };

    health = {
      path = "/";
      expectedStatus = 200;
    };
  };

  hosts = {
    la-admin-1 = {
      defaults = { };

      services = {
        navidrome = {
          subdomain = "music";
          origin = {
            scheme = "http";
            host = oci;
            port = 4533;
          };
          exposureMode = "tailscale-upstream";
          category = "app";
          access.requireCloudflareAccess = false;
          cloudflare = {
            proxied = true;
            authenticatedOriginPulls = true;
          };
          health.path = "/ping";
        };

        termix-admin = {
          subdomain = "termix";
          origin = {
            scheme = "http";
            host = "127.0.0.1";
            port = 8083;
          };
          category = "admin";
          access.oidc.enabled = true;
          access.requireCloudflareAccess = false;
        };

        kanidm-admin = {
          subdomain = "id";
          origin = {
            scheme = "https";
            host = "127.0.0.1";
            port = 8443;
          };
          upstreamTlsServerName = "id.shrublab.xyz";
          category = "admin";
          access.requireCloudflareAccess = false;
          cloudflare = {
            proxied = true;
            authenticatedOriginPulls = true;
          };
        };

        admin-homepage = {
          subdomain = "admin";
          origin = {
            scheme = "http";
            host = "127.0.0.1";
            port = 8082;
          };
          category = "admin";
        };

        cockpit-admin = {
          subdomain = "cockpit";
          path = "/la-admin-1";
          forceTrailingSlash = true;
          origin = {
            scheme = "https";
            host = "127.0.0.1";
            port = 9090;
          };
          upstreamTlsCaCertFile = "/etc/cockpit/loopback-ca.crt";
          upstreamTlsServerName = "localhost";
          category = "admin";
        };

        cockpit-oci-melb-1 = {
          subdomain = "cockpit";
          path = "/oci-melb-1";
          forceTrailingSlash = true;
          origin = {
            scheme = "https";
            host = oci;
            port = 9443;
          };
          exposureMode = "tailscale-upstream";
          category = "admin";
        };

        beszel-admin = {
          subdomain = "beszel";
          origin = {
            scheme = "http";
            host = "127.0.0.1";
            port = 8090;
          };
          category = "admin";
          access.oidc.enabled = true;
        };

        gatus-admin = {
          subdomain = "gatus";
          origin = {
            scheme = "http";
            host = "127.0.0.1";
            port = 8087;
          };
          category = "admin";
        };

        vaultwarden-admin = {
          subdomain = "vaultwarden";
          origin = {
            scheme = "http";
            host = "127.0.0.1";
            port = 8222;
          };
          category = "admin";
          access.requireCloudflareAccess = false;
        };

        quantum-admin = {
          subdomain = "quantum";
          origin = {
            scheme = "http";
            host = "127.0.0.1";
            port = 8088;
          };
          category = "admin";
          access.oidc.enabled = true;
        };

        ntfy-admin = {
          subdomain = "ntfy";
          origin = {
            scheme = "http";
            host = "127.0.0.1";
            port = 2586;
          };
          category = "admin";
          health.path = "/v1/health";
          access.requireCloudflareAccess = false;
        };

        syncthing-oci-melb-1 = {
          subdomain = "syncthing";
          path = "/oci-melb-1";
          forceTrailingSlash = true;
          stripPrefix = true;
          origin = {
            scheme = "http";
            host = oci;
            port = 8384;
          };
          upstreamHostHeader = "{upstream_hostport}";
          exposureMode = "tailscale-upstream";
          category = "admin";
        };

        slskd = {
          subdomain = "slskd";
          origin = {
            scheme = "http";
            host = oci;
            port = 5030;
          };
          exposureMode = "tailscale-upstream";
          category = "app";
        };

        tagr = {
          subdomain = "tagr";
          origin = {
            scheme = "http";
            host = oci;
            port = 3003;
          };
          exposureMode = "tailscale-upstream";
          declarePublic = true;
          category = "app";
          access.requireCloudflareAccess = true;
          cloudflare = {
            proxied = true;
            authenticatedOriginPulls = true;
          };
          health.path = "/";
        };

        karakeep = {
          subdomain = "keep";
          origin = {
            scheme = "http";
            host = oci;
            port = 3010;
          };
          exposureMode = "tailscale-upstream";
          declarePublic = true;
          category = "app";
          access.oidc.enabled = true;
          access.requireCloudflareAccess = false;
          cloudflare = {
            proxied = true;
            authenticatedOriginPulls = true;
          };
          health.path = "/";
        };

        paperless = {
          subdomain = "paper";
          origin = {
            scheme = "http";
            host = oci;
            port = 8080;
          };
          exposureMode = "tailscale-upstream";
          declarePublic = true;
          category = "app";
          access.oidc.enabled = true;
          access.requireCloudflareAccess = false;
          cloudflare = {
            proxied = true;
            authenticatedOriginPulls = true;
          };
          health.path = "/";
        };

        webhook-admin = {
          subdomain = "webhook";
          origin = {
            scheme = "http";
            host = "127.0.0.1";
            port = 9000;
          };
          exposureMode = "tailscale-only";
          category = "admin";
          health.path = "/hooks/health";
        };

        phoenix = {
          subdomain = "phoenix";
          origin = {
            scheme = "http";
            host = oci;
            port = 6006;
          };
          exposureMode = "tailscale-only";
          declarePublic = false;
          category = "admin";
          health.path = "/";
        };

        bifrost = {
          subdomain = "bifrost";
          origin = {
            scheme = "http";
            host = oci;
            port = 7411;
          };
          exposureMode = "tailscale-only";
          declarePublic = false;
          category = "admin";
          health.path = "/v1/models";
        };
      };
    };
  };
}
