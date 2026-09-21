# Host-backed origin FQDNs are composed from the canonical host ID and the
# single fleet suffix (`policy/globals.nix` `tailnet.suffix`), never
# hand-written. Every origin is absolute: the edge runs on a different host
# from the services, so a loopback origin would proxy to the edge itself.
# Plain nix attribute set on purpose: three consumers read this file as data
# (web-policy aspect, scripts/export-web-services-policy.sh,
# tests/check-web-service-catalog.sh).
#
# Every route declares its `exposureMode`, the one axis describing how the
# service is exposed: `tailscale-upstream` (published; the edge dials the
# origin's tailnet-bound socket), `tailscale-serve` (published; the origin
# socket stays loopback-bound and the providing host renders the front the edge
# dials), or `tailscale-only` (not published; machine-to-machine endpoint only),
# with `direct` reserved for an edge-local loopback upstream. No default applies
# — an unlabelled route fails evaluation.
let
  globals = import ./globals.nix;
  fqdnOf = id: "${id}.${globals.tailnet.suffix}";
  oci = fqdnOf "oci-melb-1";
  homeForge = fqdnOf "home-forge";
  la = fqdnOf "la-admin-1";
in
{
  defaults = {
    primaryDomain = "shrublab.xyz";
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
    oci-melb-1 = {
      defaults = { };

      services = {
        navidrome = {
          subdomain = "music";
          origin = {
            scheme = "http";
            # Host-backed internal origin: canonical host home-forge.
            host = homeForge;
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
          exposureMode = "tailscale-upstream";
          origin = {
            scheme = "http";
            host = la;
            port = 8083;
          };
          category = "admin";
          access.oidc.enabled = true;
          access.requireCloudflareAccess = false;
        };

        kanidm-admin = {
          subdomain = "id";
          # The provider socket is loopback-bound and TLS-only, so the providing
          # host renders the front the edge dials.
          exposureMode = "tailscale-serve";
          origin = {
            scheme = "https";
            host = la;
            port = 8443;
          };
          category = "admin";
          access.requireCloudflareAccess = false;
          cloudflare = {
            proxied = true;
            authenticatedOriginPulls = true;
          };
        };

        admin-homepage = {
          subdomain = "admin";
          exposureMode = "tailscale-upstream";
          origin = {
            scheme = "http";
            host = la;
            port = 8082;
          };
          category = "admin";
        };

        cockpit-admin = {
          subdomain = "cockpit";
          exposureMode = "tailscale-upstream";
          path = "/la-admin-1";
          forceTrailingSlash = true;
          origin = {
            scheme = "https";
            host = la;
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
          exposureMode = "tailscale-upstream";
          origin = {
            scheme = "http";
            host = la;
            port = 8090;
          };
          category = "admin";
          access.oidc.enabled = true;
        };

        gatus-admin = {
          subdomain = "gatus";
          exposureMode = "tailscale-upstream";
          origin = {
            scheme = "http";
            host = la;
            port = 8087;
          };
          category = "admin";
        };

        vaultwarden-admin = {
          subdomain = "vaultwarden";
          exposureMode = "tailscale-upstream";
          origin = {
            scheme = "http";
            host = la;
            port = 8222;
          };
          category = "admin";
          access.requireCloudflareAccess = false;
        };

        ntfy-admin = {
          subdomain = "ntfy";
          exposureMode = "tailscale-upstream";
          origin = {
            scheme = "http";
            host = la;
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

        syncthing-home-forge = {
          subdomain = "syncthing";
          path = "/home-forge";
          forceTrailingSlash = true;
          stripPrefix = true;
          origin = {
            scheme = "http";
            host = homeForge;
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
            host = homeForge;
            port = 5030;
          };
          exposureMode = "tailscale-upstream";
          category = "app";
        };

        tagr = {
          subdomain = "tagr";
          origin = {
            scheme = "http";
            host = homeForge;
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
            host = la;
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

        # Private machine-to-machine service with no ingress route at all. It is
        # listed here because this host key owns the fleet's service topology;
        # the catalog projects it as a tailscale-only endpoint, and both the
        # provider (listen address) and the publisher (serverUrl) read that one
        # declaration, so the port cannot drift.
        niks3-write = {
          subdomain = null;
          origin = {
            scheme = "http";
            host = oci;
            port = 5751;
          };
          exposureMode = "tailscale-only";
          declarePublic = false;
          category = "infra";
          health.path = "/";
        };
      };
    };
  };
}
