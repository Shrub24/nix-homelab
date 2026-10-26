# Placement, not addresses: a route declares `origin.provider` plus shape; dial addresses derive in
# lib/policy.nix and identity stays literal. exposureMode has no default.
{ canonicalServices }:
let
  globals = import ./globals.nix;

  # Origin derives from the canonical record; named errors keep a missing service from becoming an attribute error.
  canonicalOrigin =
    service: endpoint:
    let
      record =
        canonicalServices.${service}
          or (throw "web-services: nix-fleet declares no canonical service '${service}'");
      endpointRecord =
        record.endpoints.${endpoint}
          or (throw "web-services: canonical service '${service}' has no endpoint '${endpoint}'");
      tailnet =
        endpointRecord.tailnet
          or (throw "web-services: canonical service '${service}' endpoint '${endpoint}' has no tailnet route");
    in
    {
      provider = tailnet.host;
      scheme = tailnet.scheme or "http";
      inherit (tailnet) port;
    };
in
{
  defaults = {
    primaryDomain = globals.domain;
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

        # Published for the client cutover: the provider now issues application identity,
        # and its issuer URL has to resolve before any client can be pointed at it.
        authentik-admin = {
          subdomain = "auth";
          exposureMode = "direct";
          origin = {
            scheme = "http";
            provider = "oci-melb-1";
            port = 9002;
          };
          category = "admin";
          declarePublic = true;
          publish = true;
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
          # Provider and transport come from the canonical ntfy record.
          origin = canonicalOrigin "ntfy" "api";
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
          access.policies = [
            "allow_admins"
            "allow_users"
          ];
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

        # Published with their own OIDC login; loopback sockets, so the edge dials them locally.
        # Their clients cannot carry an Access session.
        actual = {
          subdomain = "budget";
          origin = {
            scheme = "http";
            provider = "oci-melb-1";
            port = 5006;
          };
          exposureMode = "direct";
          category = "app";
          access.oidc.enabled = true;
          access.requireCloudflareAccess = false;
        };

        memos = {
          subdomain = "memos";
          origin = {
            scheme = "http";
            provider = "oci-melb-1";
            port = 5230;
          };
          exposureMode = "direct";
          category = "app";
          access.oidc.enabled = true;
          access.requireCloudflareAccess = false;
        };

        tududi = {
          subdomain = "tududi";
          origin = {
            scheme = "http";
            provider = "oci-melb-1";
            port = 3002;
          };
          exposureMode = "direct";
          category = "app";
          access.oidc.enabled = true;
          access.requireCloudflareAccess = false;
        };

        # Kanidm OIDC gates the web app; Access is off because OPDS and e-reader clients cannot pass it.
        bookorbit = {
          subdomain = "books";
          origin = {
            scheme = "http";
            provider = "home-forge";
            port = 8086;
          };
          exposureMode = "tailscale-upstream";
          category = "app";
          access.oidc.enabled = true;
          access.requireCloudflareAccess = false;
          cloudflare = {
            proxied = true;
            authenticatedOriginPulls = true;
          };
          health.path = "/api/v1/health";
        };

        # The apex is a permanent redirect with no application behind it.
        # No login or Access application: the redirect carries no data, and Access would block arrivals.
        apex = {
          subdomain = null;
          redirectTo = "https://auth.${globals.domain}";
          exposureMode = "direct";
          access.oidc.enabled = false;
          access.requireCloudflareAccess = false;
        };

        homarr = {
          subdomain = "home";
          origin = {
            scheme = "http";
            provider = "oci-melb-1";
            port = 7575;
          };
          exposureMode = "tailscale-serve";
          category = "app";
          access.oidc.enabled = true;
          access.requireCloudflareAccess = false;
          # Published: Kanidm login is the gate; its `groups` decide administration.
        };

        # Google sign-in gates the app; the webhook stays public, so neither Access nor app OIDC applies.
        inbox-zero = {
          subdomain = "inbox";
          origin = {
            scheme = "http";
            provider = "oci-melb-1";
            port = 3004;
          };
          exposureMode = "direct";
          category = "app";
          access.oidc.enabled = false;
          access.requireCloudflareAccess = false;
        };

        # The aspect reads the port from here, so socket and route cannot drift. Access stays
        # off: device ingest cannot present an Access session.
        geopulse = {
          subdomain = "geo";
          origin = {
            scheme = "http";
            provider = "oci-melb-1";
            port = 8085;
          };
          # tailscale-serve: the front binds loopback, and the provider renders the private front for the OIDC callback.
          exposureMode = "tailscale-serve";
          declarePublic = true;
          publish = true;
          category = "app";
          access.oidc.enabled = true;
          access.requireCloudflareAccess = false;
          health.path = "/";
          # Permit-list only the unauthenticated leaves this deployment does not need.
          # Device ingest is the acceptance path, and the SPA uses geocoding; both stay open.
          deniedPaths = [
            "/api/prometheus/metrics" # operational metrics
            "/api/health" # diagnostics
            "/api/maintenance/status" # diagnostics
            "/api/version" # version diagnostics
            "/api/version/status" # version diagnostics
            "/api/home/content" # unauthenticated home copy
            "/api/shared/*" # public share links (a non-goal)
            "/api/overland" # unused ingest sources
            "/api/traccar"
            "/api/colota"
            "/api/homeassistant"
            "/api/homeassistant/*"
            "/api/dawarich/*"
            "/api/ai" # AI is a non-goal; closed publicly
            "/api/ai/*"
            "/mcp" # MCP tool surface
            "/mcp/*"
          ];
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
            provider = "home-forge";
            # 3030, not 3000: Grafana owns 3000 on home-forge.
            port = 3030;
          };
          exposureMode = "tailscale-upstream";
          category = "admin";
          # Both gates: Cloudflare Access at the edge, langfuse's own OIDC in the app.
          access.oidc.enabled = true;
          access.requireCloudflareAccess = true;
          cloudflare = {
            proxied = true;
            authenticatedOriginPulls = true;
          };
        };

        latitude = {
          subdomain = "latitude";
          origin = {
            scheme = "http";
            provider = "home-forge";
            port = 3110;
          };
          exposureMode = "tailscale-upstream";
          category = "admin";
          # The app's magic-link sign-in is the gate; Access is the outer wall.
          access.requireCloudflareAccess = true;
          cloudflare = {
            proxied = true;
            authenticatedOriginPulls = true;
          };
          health.path = "/";
        };

        latitude-api = {
          subdomain = "latitude-api";
          origin = {
            scheme = "http";
            provider = "home-forge";
            port = 3001;
          };
          exposureMode = "tailscale-upstream";
          # An API origin: the browser calls it directly, so it is a machine endpoint with no dashboard tile.
          category = "infra";
          # No interactive gate: the browser and the web container call this origin directly, and Access would break sign-in.
          access.requireCloudflareAccess = false;
          cloudflare = {
            proxied = true;
            authenticatedOriginPulls = true;
          };
          health.path = "/health";
        };

        bifrost = {
          subdomain = "bifrost";
          # Provider and transport are the canonical bifrost/embeddings record's.
          origin = canonicalOrigin "bifrost" "embeddings";
          exposureMode = "tailscale-only";
          declarePublic = false;
          category = "admin";
          health.path = "/v1/models";
        };

        # Private machine endpoint with no ingress route; provider and publisher read one declaration, so the port cannot drift.
        niks3-write = {
          subdomain = null;
          # Provider and transport are the canonical niks3-write record's.
          origin = canonicalOrigin "niks3-write" "api";
          exposureMode = "tailscale-only";
          declarePublic = false;
          category = "infra";
          health.path = "/";
        };

        # Tailnet-only WebUI with no public route; the listener is reached through the trusted tailscale0 interface.
        qbittorrent = {
          subdomain = null;
          origin = {
            scheme = "http";
            provider = "home-forge";
            port = 8091;
          };
          exposureMode = "tailscale-only";
          declarePublic = false;
          category = "infra";
          health.path = "/";
        };

        # Tailnet-only indexer UI with no public route; the listener is reached through the trusted tailscale0 interface.
        prowlarr = {
          subdomain = null;
          origin = {
            scheme = "http";
            provider = "home-forge";
            port = 9696;
          };
          exposureMode = "tailscale-only";
          declarePublic = false;
          category = "infra";
          health.path = "/";
        };

        # OTLP ingest is a machine endpoint with no interactive gate. LAT_INGEST_URL reads this port.
        latitude-ingest = {
          subdomain = null;
          origin = {
            scheme = "http";
            provider = "home-forge";
            port = 3002;
          };
          exposureMode = "tailscale-only";
          declarePublic = false;
          category = "admin";
          health.path = "/health";
        };

        # Observability store placed where its disks are: three private ingest endpoints, with Grafana behind Access.
        # The store reads these declarations for its listeners.
        victoriametrics = {
          subdomain = null;
          origin = {
            scheme = "http";
            provider = "home-forge";
            port = 8428;
          };
          exposureMode = "tailscale-only";
          declarePublic = false;
          category = "infra";
          health.path = "/health";
        };

        victorialogs = {
          subdomain = null;
          origin = {
            scheme = "http";
            provider = "home-forge";
            port = 9428;
          };
          exposureMode = "tailscale-only";
          declarePublic = false;
          category = "infra";
          health.path = "/health";
        };

        victoriatraces = {
          subdomain = null;
          origin = {
            scheme = "http";
            provider = "home-forge";
            port = 10428;
          };
          exposureMode = "tailscale-only";
          declarePublic = false;
          category = "infra";
          health.path = "/health";
        };

        grafana = {
          subdomain = "grafana";
          origin = {
            scheme = "http";
            provider = "home-forge";
            port = 3000;
          };
          exposureMode = "tailscale-upstream";
          category = "admin";
          health.path = "/api/health";
        };

        # Home Assistant shares home-forge's namespace, so the edge dials the provider's tailnet listener directly.
        # Withheld until accepted: released by flipping `publish`; its own login is the only gate until then.
        home-assistant = {
          subdomain = "hass";
          origin = {
            scheme = "http";
            provider = "home-forge";
            port = 8123;
          };
          exposureMode = "tailscale-upstream";
          category = "app";
          publish = false;
          # Behind Access once published; Home Assistant's own auth is the inner gate, not Kanidm.
          access.requireCloudflareAccess = true;
          cloudflare = {
            proxied = true;
            authenticatedOriginPulls = true;
          };
        };
      };
    };
  };
}
