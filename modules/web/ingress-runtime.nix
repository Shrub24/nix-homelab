# Ingress runtime contributor of the `ingress` aspect: deferredModule values merge
# across sibling files, so the host selects one aspect name.
_: {
  flake.modules.nixos.ingress =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.services.ingress;
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };

      routeNames = builtins.attrNames cfg.routes;
      routeByName = name: cfg.routes.${name};
      isPublicRoute = route: route.exposureMode != "tailscale-only";
      publicRouteNames = builtins.filter (name: isPublicRoute (routeByName name)) routeNames;
      publicRoutes = map routeByName publicRouteNames;

      hostForRoute =
        route:
        if route.subdomain != null then "${route.subdomain}.${cfg.primaryDomain}" else cfg.primaryDomain;

      siteHosts = lib.unique (map hostForRoute publicRoutes);

      needsAccessHeader = route: route.cloudflareAccessRequired;

      sanitize = value: lib.replaceStrings [ "." "-" "/" "@" ] [ "_" "_" "_" "_" ] value;

      mkRouteHandle =
        name: route:
        let
          id = sanitize name;
          responseHeaders = lib.concatStringsSep "\n          " (
            lib.mapAttrsToList (
              headerName: headerValue: "header ${headerName} ${builtins.toJSON headerValue}"
            ) route.responseHeaders
          );
          accessGuard =
            if needsAccessHeader route then
              ''
                @${id}_missing_access not header Cf-Access-Authenticated-User-Email *
                respond @${id}_missing_access "Cloudflare Access required" 403
              ''
            else
              "";
          upstreamTransport =
            if
              route.upstreamTlsInsecure
              || route.upstreamTlsCaCertFile != null
              || route.upstreamTlsServerName != null
            then
              ''
                transport http {
                  ${lib.optionalString route.upstreamTlsInsecure "tls_insecure_skip_verify"}
                  ${lib.optionalString (
                    route.upstreamTlsCaCertFile != null
                  ) "tls_trust_pool file ${route.upstreamTlsCaCertFile}"}
                  ${lib.optionalString (
                    route.upstreamTlsServerName != null
                  ) "tls_server_name ${route.upstreamTlsServerName}"}
                }
              ''
            else
              "";
        in
        if route.path == "/" then
          ''
            # ${name} (${route.exposureMode})
            handle {
              ${accessGuard}
              ${responseHeaders}
              reverse_proxy ${route.upstream} {
                header_up Host ${route.upstreamHostHeader}
                header_up X-Forwarded-Proto {scheme}
                header_up X-Forwarded-For {remote_host}
                ${upstreamTransport}
              }
            }
          ''
        else if route.stripPrefix then
          ''
            # ${name} (${route.exposureMode})
            ${lib.optionalString route.forceTrailingSlash "redir ${route.path} ${route.path}/ 308"}
            handle_path ${route.path}* {
              ${accessGuard}
              ${responseHeaders}
              reverse_proxy ${route.upstream} {
                header_up Host ${route.upstreamHostHeader}
                header_up X-Forwarded-Proto {scheme}
                header_up X-Forwarded-For {remote_host}
                ${upstreamTransport}
              }
            }
          ''
        else
          ''
            # ${name} (${route.exposureMode})
            ${lib.optionalString route.forceTrailingSlash "redir ${route.path} ${route.path}/ 308"}
            @${id}_path path ${route.path}*
            handle @${id}_path {
              ${accessGuard}
              ${responseHeaders}
              reverse_proxy ${route.upstream} {
                header_up Host ${route.upstreamHostHeader}
                header_up X-Forwarded-Proto {scheme}
                header_up X-Forwarded-For {remote_host}
                ${upstreamTransport}
              }
            }
          '';

      hostRouteNames =
        host: builtins.filter (name: hostForRoute (routeByName name) == host) publicRouteNames;

      hostAopValues =
        host: map (name: (routeByName name).authenticatedOriginPullsRequired) (hostRouteNames host);

      hostRequiresAop = host: builtins.any (value: value) (hostAopValues host);

      hostHasMixedAopRequirement =
        host:
        let
          values = lib.unique (hostAopValues host);
        in
        builtins.length values > 1;

      mTlsBlock =
        host:
        if cfg.authenticatedOriginPulls.enable && hostRequiresAop host then
          ''
            client_auth {
              mode require_and_verify
              trust_pool file {
                pem_file ${cfg.authenticatedOriginPulls.caCertFile}
              }
            }
          ''
        else
          "";

      trustedProxyArgs = lib.concatStringsSep " " cfg.trustedProxyCidrs;

      caddyGlobal =
        if cfg.role == "edge" then
          ''
            {
              servers {
                trusted_proxies static ${trustedProxyArgs}
                client_ip_headers CF-Connecting-IP X-Forwarded-For
              }
            }
          ''
        else
          "";

      renderSite =
        host:
        let
          namesForHost = builtins.filter (name: hostForRoute (routeByName name) == host) publicRouteNames;
          sortedNames = lib.sort (
            a: b: builtins.stringLength (routeByName a).path > builtins.stringLength (routeByName b).path
          ) namesForHost;
          routeBlocks = lib.concatStringsSep "\n" (
            map (name: mkRouteHandle name (routeByName name)) sortedNames
          );
        in
        ''
          ${host} {
            tls /var/lib/acme/${cfg.primaryDomain}/fullchain.pem /var/lib/acme/${cfg.primaryDomain}/key.pem {
              ${mTlsBlock host}
            }
            encode zstd
          ${routeBlocks}
          }
        '';

      caddyfile = pkgs.writeText "Caddyfile-edge-proxy" ''
        ${caddyGlobal}

        ${lib.concatStringsSep "\n\n" (map renderSite siteHosts)}
      '';

      certExtraDomains = [ "*.${cfg.primaryDomain}" ];

      routeAssertions =
        lib.map (
          name:
          let
            route = routeByName name;
          in
          {
            assertion = lib.hasPrefix "/" route.path;
            message = "services.ingress route '${name}' path must start with '/'.";
          }
        ) routeNames
        ++ lib.map (
          name:
          let
            route = routeByName name;
          in
          {
            assertion = route.exposureMode == "tailscale-only" || route.declarePublic;
            message = "services.ingress route '${name}' must set declarePublic=true for public exposure modes.";
          }
        ) routeNames;
    in
    {
      options.services.ingress = {
        enable = lib.mkEnableOption "the host-level ingress composition (edge or origin role)";

        role = lib.mkOption {
          type = lib.types.enum [
            "none"
            "edge"
            "origin"
          ];
          default = "none";
          description = "Host ingress role: none, edge (publishes routes), or origin (private upstream only).";
        };

        primaryDomain = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Primary domain used for all ingress subdomain/path routing.";
        };

        acmeEmail = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Email used for ACME registration when role=edge.";
        };

        cloudflareCredentialsFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Path to env-file containing CLOUDFLARE_DNS_API_TOKEN for ACME DNS-01.";
        };

        trustedProxyCidrs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "173.245.48.0/20"
            "103.21.244.0/22"
            "103.22.200.0/22"
            "103.31.4.0/22"
            "141.101.64.0/18"
            "108.162.192.0/18"
            "190.93.240.0/20"
            "188.114.96.0/20"
            "197.234.240.0/22"
            "198.41.128.0/17"
            "162.158.0.0/15"
            "104.16.0.0/13"
            "104.24.0.0/14"
            "172.64.0.0/13"
            "131.0.72.0/22"
            "2400:cb00::/32"
            "2606:4700::/32"
            "2803:f800::/32"
            "2405:b500::/32"
            "2405:8100::/32"
            "2a06:98c0::/29"
            "2c0f:f248::/32"
          ];
          description = "Trusted proxy CIDRs for preserving original client IP headers (Cloudflare ranges by default).";
        };

        authenticatedOriginPulls = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Require Cloudflare Authenticated Origin Pulls (mTLS) for edge routes.";
          };

          caCertFile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Path to CA cert file used to verify Cloudflare origin-pull client certs.";
          };
        };

        secretFiles.host = secretHelpers.mkSecretFileOption "the Cloudflare DNS-01 token used by the edge role";

        routes = lib.mkOption {
          default = { };
          description = "Route map keyed by route name.";
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                subdomain = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "Optional subdomain label under primaryDomain.";
                };

                path = lib.mkOption {
                  type = lib.types.str;
                  default = "/";
                  description = "Path prefix for route matching.";
                };

                upstream = lib.mkOption {
                  type = lib.types.str;
                  description = "Reverse-proxy upstream target (e.g. http://127.0.0.1:4533).";
                };

                exposureMode = lib.mkOption {
                  type = lib.types.enum [
                    "direct"
                    "tailscale-upstream"
                    "tailscale-serve"
                    "tailscale-only"
                  ];
                  default = "tailscale-upstream";
                  description = "Exposure mode for this route: how the edge reaches it and whether it is published.";
                };

                declarePublic = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Explicit opt-in required for public route rendering.";
                };

                category = lib.mkOption {
                  type = lib.types.enum [
                    "app"
                    "admin"
                    "sensitive"
                  ];
                  default = "app";
                  description = "Route category used by policy guardrails.";
                };

                cloudflareAccessRequired = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Require Cloudflare Access identity header before proxying.";
                };

                stripPrefix = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Use handle_path to strip path prefix before proxying.";
                };

                forceTrailingSlash = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Redirect the exact route path to a trailing-slash variant before proxying.";
                };

                responseHeaders = lib.mkOption {
                  type = lib.types.attrsOf lib.types.str;
                  default = { };
                  description = "Optional response headers injected before proxying for this route.";
                };

                upstreamHostHeader = lib.mkOption {
                  type = lib.types.str;
                  default = "{host}";
                  description = "Value used for the upstream Host header when proxying this route.";
                };

                authenticatedOriginPullsRequired = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "Whether this route requires Cloudflare Authenticated Origin Pulls (mTLS) at host TLS layer.";
                };

                upstreamTlsInsecure = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Disable TLS verification when proxying to HTTPS upstream with self-signed/private certs.";
                };

                upstreamTlsCaCertFile = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "Optional CA certificate file trusted for HTTPS upstream verification.";
                };

                upstreamTlsServerName = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "Optional TLS server name override used when verifying HTTPS upstreams.";
                };
              };
            }
          );
        };
      };

      config = {
        assertions = [
          (secretHelpers.mkRequiredSecretAssertion {
            enable = cfg.enable && cfg.role == "edge";
            file = cfg.secretFiles.host;
            feature = "services.ingress";
            label = "secretFiles.host";
          })
          {
            assertion = cfg.role != "edge" || cfg.primaryDomain != "";
            message = "services.ingress requires primaryDomain when role=edge.";
          }
          {
            assertion = cfg.role != "edge" || cfg.acmeEmail != "";
            message = "services.ingress requires acmeEmail when role=edge.";
          }
          {
            assertion = cfg.role != "edge" || cfg.cloudflareCredentialsFile != null;
            message = "services.ingress requires cloudflareCredentialsFile when role=edge.";
          }
          {
            assertion = !cfg.authenticatedOriginPulls.enable || cfg.authenticatedOriginPulls.caCertFile != null;
            message = "services.ingress requires authenticatedOriginPulls.caCertFile when authenticatedOriginPulls.enable=true.";
          }
          {
            assertion = cfg.authenticatedOriginPulls.enable || !(builtins.any hostRequiresAop siteHosts);
            message = "services.ingress has public hosts requiring authenticated origin pulls, but authenticatedOriginPulls.enable=false.";
          }
          {
            assertion = !(builtins.any hostHasMixedAopRequirement siteHosts);
            message = "services.ingress cannot mix authenticatedOriginPullsRequired true/false routes on the same host.";
          }
          {
            assertion =
              !(builtins.any (
                name:
                let
                  route = routeByName name;
                in
                route.upstreamTlsInsecure && route.upstreamTlsCaCertFile != null
              ) routeNames);
            message = "services.ingress routes cannot set both upstreamTlsInsecure=true and upstreamTlsCaCertFile.";
          }
          {
            assertion = cfg.role == "edge" || cfg.routes == { };
            message = "services.ingress routes may only be declared when role=edge.";
          }
        ]
        ++ routeAssertions;

        networking.firewall.allowedTCPPorts = lib.mkIf (cfg.role == "edge" && publicRouteNames != [ ]) [
          80
          443
        ];

        security.acme = lib.mkIf (cfg.role == "edge") {
          acceptTerms = true;
          defaults.email = cfg.acmeEmail;
          certs.${cfg.primaryDomain} = {
            domain = cfg.primaryDomain;
            extraDomainNames = certExtraDomains;
            dnsProvider = "cloudflare";
            environmentFile = cfg.cloudflareCredentialsFile;
            group = "caddy";
          };
        };

        services.caddy = lib.mkIf (cfg.role == "edge") {
          enable = true;
          configFile = caddyfile;
        };

        systemd.services.caddy = lib.mkIf (cfg.role == "edge") {
          wants = [ "acme-${cfg.primaryDomain}.service" ];
          after = [ "acme-${cfg.primaryDomain}.service" ];
        };

        # Cloudflare DNS-01 credentials, materialized from the host secret file
        # when this host is the edge.
        services.ingress.cloudflareCredentialsFile = lib.mkIf (cfg.enable && cfg.role == "edge") (
          config.sops.templates."caddy-cloudflare.env".path
        );

        sops.templates."caddy-cloudflare.env" = lib.mkIf (cfg.enable && cfg.role == "edge") {
          owner = "root";
          group = "root";
          mode = "0400";
          content = ''
            CLOUDFLARE_DNS_API_TOKEN=${config.sops.placeholder.cloudflare_dns_api_token}
          '';
        };

        sops.secrets = lib.mkIf (cfg.enable && cfg.role == "edge") (
          secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
            cloudflare_dns_api_token = {
              key = "cloudflare/dns_api_token";
              path = "/run/secrets/cloudflare.dns_api_token";
              owner = "root";
              group = "root";
            };
          }
        );
      };
    };
}
