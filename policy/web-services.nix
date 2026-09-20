# Placement, not addresses: every route declares `origin.provider` — the
# canonical host ID that runs the service — plus scheme and port. Dial
# addresses are derived where they are consumed, by two distinct policies
# over the same placement: `lib/policy.nix` renders an ingress upstream from
# the route's `exposureMode` (`direct` loops back edge-locally; every tailnet
# mode dials the provider by FQDN, even when provider and edge coincide,
# because its socket belongs to the tailnet), while a private service's
# machine-to-machine `endpoint` resolves against the evaluating host and
# loops back when colocated with its provider. Moving the edge or a workload
# therefore changes placement here — never a consumer's config — and
# identity (public URLs, OIDC endpoints, TLS server names) stays literal and
# stable, separate from transport. Plain nix attribute set on purpose: three
# consumers read this file as data (web-policy aspect,
# scripts/export-web-services-policy.sh, tests/check-web-service-catalog.sh).
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
            provider = "home-forge";
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
            provider = "la-admin-1";
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
            provider = "la-admin-1";
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
            provider = "la-admin-1";
            port = 8082;
          };
          category = "admin";
        };

        cockpit-oci-melb-1 = {
          subdomain = "cockpit";
          path = "/oci-melb-1";
          forceTrailingSlash = true;
          origin = {
            scheme = "https";
            provider = "oci-melb-1";
            port = 9443;
          };
          # Tailnet-bound bespoke front (TD-29): the edge reaches the
          # tailnet socket by provider name, never loopback — even though
          # provider and edge coincide on oci-melb-1.
          exposureMode = "tailscale-upstream";
          category = "admin";
        };

        beszel-admin = {
          subdomain = "beszel";
          exposureMode = "tailscale-upstream";
          origin = {
            scheme = "http";
            provider = "la-admin-1";
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
            provider = "la-admin-1";
            port = 8087;
          };
          category = "admin";
        };

        vaultwarden-admin = {
          subdomain = "vault";
          exposureMode = "tailscale-upstream";
          origin = {
            scheme = "http";
            provider = "la-admin-1";
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
            provider = "la-admin-1";
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
            provider = "oci-melb-1";
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
            provider = "home-forge";
            port = 8384;
          };
          upstreamHostHeader = "{upstream_hostport}";
          exposureMode = "tailscale-upstream";
          category = "admin";
        };

        search = {
          subdomain = "search";
          origin = {
            scheme = "http";
            provider = "home-forge";
            port = 4444;
          };
          exposureMode = "tailscale-upstream";
          category = "app";
          access.requireCloudflareAccess = true;
          cloudflare = {
            proxied = true;
            authenticatedOriginPulls = true;
          };
        };

        slskd = {
          subdomain = "slskd";
          origin = {
            scheme = "http";
            provider = "home-forge";
            port = 5030;
          };
          exposureMode = "tailscale-upstream";
          category = "app";
        };

        tagr = {
          subdomain = "tagr";
          origin = {
            scheme = "http";
            provider = "home-forge";
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
            provider = "oci-melb-1";
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
            provider = "oci-melb-1";
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
            provider = "la-admin-1";
            port = 9000;
          };
          exposureMode = "tailscale-only";
          category = "admin";
          health.path = "/hooks/health";
        };

        langfuse = {
          subdomain = "langfuse";
          origin = {
            scheme = "http";
            provider = "oci-melb-1";
            port = 3000;
          };
          exposureMode = "tailscale-upstream";
          category = "admin";
          access.requireCloudflareAccess = true;
          cloudflare = {
            proxied = true;
            authenticatedOriginPulls = true;
          };
        };

        bifrost = {
          subdomain = "bifrost";
          origin = {
            scheme = "http";
            provider = "oci-melb-1";
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
            provider = "oci-melb-1";
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
