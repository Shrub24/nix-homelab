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
# stable, separate from transport. Provider placement and transport for a route
# that mirrors a canonical cross-fleet service come from nix-fleet's service
# inventory (`lib/service-inventory.nix`), threaded in as the `canonicalServices`
# argument: the record declares host, scheme and port once, and the route keeps
# only its own subdomain, exposure, access and health policy. The file stays
# plain data — it takes no flake reference of its own — and four consumers read
# it as data (the web-policy aspect, scripts/export-web-services-policy.sh,
# tests/check-web-service-catalog.sh, tests/check-web-services-policy.sh).
#
# Every route declares its `exposureMode`, the one axis describing how the
# service is exposed: `tailscale-upstream` (published; the edge dials the
# origin's tailnet-bound socket), `tailscale-serve` (published; the origin
# socket stays loopback-bound and the providing host renders the front the edge
# dials), or `tailscale-only` (not published; machine-to-machine endpoint only),
# with `direct` reserved for an edge-local loopback upstream. No default applies
# — an unlabelled route fails evaluation.
{ canonicalServices }:
let
  globals = import ./globals.nix;

  # A route whose provider is a canonical cross-fleet service derives its whole
  # origin from that record, so the provider host ID and port are declared once
  # (nix-fleet's service inventory) and cannot drift from the provider's own
  # listener. Named errors keep a missing service, endpoint or route from
  # degrading into an attribute-error message.
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
          # Provider and transport are the canonical ntfy record's; the route
          # keeps only its own exposure, access and health policy.
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

        # Published household apps with their own OIDC login. Actual and Memos
        # bind loopback on this host, so the edge dials them locally (`direct`).
        # tududi's container publishes its port to loopback only, which keeps the
        # same edge-local socket. Their clients cannot carry an Access session.
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

        # Keep the OIDC-protected route private through Tailscale Serve until
        # Homarr has been bootstrapped and its public edge route is released.
        # The apex answers with a permanent redirect to the dashboard. It is a
        # landing point with no application behind it, so no session or cookie
        # can be scoped to the registrable domain. It needs no login and no Access
        # application: the redirect carries no data, and Access on the apex would
        # block the browsers that arrive there.
        apex = {
          subdomain = null;
          redirectTo = "https://home.shrublab.xyz";
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
          # Published: the Kanidm login is the gate and `groups` from Kanidm
          # decides administration, so there is nothing left to withhold (D-103).
        };

        # Google sign-in gates the app itself; the webhook must stay public, so
        # neither Access nor application OIDC sits in front of it.
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

        # GeoPulse's private front-end listener. The aspect reads this declaration
        # for the port its own listener binds, so the socket and the route cannot
        # drift; the public identity (subdomain, exposure, the bootstrap gate) is
        # the later identity task, and until then the route carries no public URL
        # and therefore no edge route, dashboard tile or uptime check.
        # Public identity from the start, but not yet published: the OIDC callback
        # derives from this origin while the edge withholds the route, so no
        # Access-free site answers before the private bootstrap is done. Publishing
        # it is this `publish` field and nothing else. Access stays off because
        # device ingest cannot present an interactive Access session and the
        # application authenticates its own callers.
        geopulse = {
          subdomain = "geo";
          origin = {
            scheme = "http";
            provider = "oci-melb-1";
            port = 8085;
          };
          # `tailscale-serve`, not `direct`: the front end binds loopback, so a
          # co-located edge route would have nothing to dial, and until the route
          # is published there would be no private way in at all. The provider
          # renders the front itself, which is also what makes the private OIDC
          # callback reachable for first-time onboarding.
          exposureMode = "tailscale-serve";
          declarePublic = true;
          publish = false;
          category = "app";
          access.oidc.enabled = true;
          access.requireCloudflareAccess = false;
          health.path = "/";
          # GP-5: surfaces GeoPulse leaves unauthenticated that this deployment does
          # not need. Each entry is the permit-list pattern for its own path, so the
          # authenticated management APIs beside them keep working. Device ingest
          # (`/api/owntracks`, `/api/gpslogger`) and `/api/geocoding/*` stay open:
          # the first is the acceptance path and the SPA has geocoding features.
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
          # The app's own gate is a magic-link sign-in; generic OIDC is an
          # enterprise-flagged path upstream, so Access carries the outer wall.
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
          # An API origin, not a page: the web app's browser calls it directly,
          # so it is a machine endpoint and earns no dashboard app.
          category = "infra";
          # Deliberately no interactive gate: the browser calls this origin
          # directly (the web app does not proxy the API) and so does the web
          # container, so an Access challenge here breaks sign-in. Latitude's own
          # auth authorizes every route on it.
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

        # Private machine-to-machine service with no ingress route at all. It is
        # listed here because this host key owns the fleet's service topology;
        # the catalog projects it as a tailscale-only endpoint, and both the
        # provider (listen address) and the publisher (serverUrl) read that one
        # declaration, so the port cannot drift.
        niks3-write = {
          subdomain = null;
          # Provider and transport are the canonical niks3-write record's.
          origin = canonicalOrigin "niks3-write" "api";
          exposureMode = "tailscale-only";
          declarePublic = false;
          category = "infra";
          health.path = "/";
        };

        # Latitude's OTLP/HTTP ingest is the same kind of endpoint for the other
        # telemetry direction: machine exporters dial it, so it has no ingress
        # route and cannot sit behind an interactive gate. The aspect reads this
        # declaration for LAT_INGEST_URL, so the port cannot drift.
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

        # The fleet's observability store, placed on the host with the disks for
        # it. The three ingest endpoints are private machine routes — a
        # collector dials them over the tailnet and no ingress route exists —
        # while Grafana is the human front end and stays behind Access on the
        # public edge. The store aspect reads these declarations for its
        # listeners, so a port is stated once.
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

        # Home automation. The container shares home-forge's network namespace,
        # so the origin is the provider's own listener on the provider's tailnet
        # name — the edge dials it directly, with no provider-side front.
        #
        # Withheld until the instance is onboarded and accepted: released by
        # flipping `publish`, the same single edit Homarr uses. Until then it
        # is reached on the tailnet at the provider's port, and Home Assistant's
        # own login is the only gate, so nothing new sits in the login path.
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
          # Once published, Access is the outer wall and Home Assistant's login
          # the inner one. `access.oidc.enabled` stays off: this instance uses
          # Home Assistant's own auth, not Kanidm.
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
