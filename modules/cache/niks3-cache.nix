# Niks3 cache-server aspect. nix-fleet owns the server mechanism (the fail-closed
# option surface, the upstream niks3 service wiring, the secret registrations);
# this contributor supplies the fleet's deployment policy — the S3 coordinates
# from policy/globals.nix and the public cache URL — and leaves the secret-file
# bindings to the host that owns them.
{ inputs, ... }:
{
  flake.modules.nixos.niks3-cache =
    {
      config,
      lib,
      options,
      ...
    }:
    let
      globals = import ../../policy/globals.nix;
      s3 = globals.s3 or { };
      # niks3 derives TLS from useSSL, so the endpoint carries no protocol.
      s3Host = builtins.replaceStrings [ "https://" "http://" ] [ "" "" ] (s3.endpoint or "");
      # The one workflow that mints a pushing token — nix-fleet's reusable build
      # plane — plus the claims that read the same in both GitHub subject forms:
      # an immutable-subject repository still reports these values.
      ciClaims = {
        repository_owner_id = [ "20262061" ];
        ref = [ "refs/heads/main" ];
        job_workflow_ref = [ "Shrub24/nix-fleet/.github/workflows/build-push-cache.yml@*" ];
      };
      # The repositories whose CI may publish, and therefore the pin namespaces
      # below: one reserved namespace per repository.
      ciRepositories = [
        "nix-fleet"
        "nix-homelab"
        "nix-dotfiles"
      ];
      niks3WritePort = config.repo.web.catalog."niks3-write".endpoint.port;
      # nix-fleet's telemetry contract declares the scrape registry, and the cache
      # aspect is placeable on a host that runs no metrics lane, so the binding is
      # probed and applied only where the registry exists.
      hasTelemetryScrape = lib.hasAttrByPath [ "services" "telemetry" "scrape" ] options;
    in
    {
      # The shared aspect renders `services.niks3.*` but does not import the
      # upstream server module (that is the consumer's seam), so the aspect owns
      # it here: any host selecting `niks3-cache` gets the option surface.
      imports = [
        inputs.niks3.nixosModules.niks3
        inputs.nix-fleet.modules.nixos.niks3-cache
      ];

      services.niks3-cache = {
        s3 = {
          endpoint = lib.mkDefault s3Host;
          region = lib.mkDefault (s3.region or "");
        };
        cacheUrl = lib.mkDefault "https://cache.shrublab.xyz";
        # CI federation: GitHub Actions authenticates to the push API with
        # short-lived OIDC tokens (nix-fleet's build-push-cache workflow), so no
        # long-lived write secret exists in any repository. Reads are not part
        # of this: the public substituter serves narinfo/nar from R2 behind
        # Cloudflare, and niks3's own read proxy is not on that path — binding a
        # provider gates the API, where write implies read for tokens only.
        # Claims, not the subject. GitHub mints `sub` either in the name-only
        # form or in an immutable owner-ID/repository-ID form, and the choice
        # follows the repository's age rather than ours — repos created on or
        # after 2026-07-15 default to immutable, which nix-fleet (created
        # 2026-09-21) does, so the former `repo:Shrub24/*` subject pattern
        # stopped matching it. Bound claims read the same in both forms: niks3
        # ANDs the listed claims and ORs the patterns inside each one, so naming
        # the owner ID, the calling repository, the branch and the one workflow
        # that mints a pushing token is stronger than pattern-matching `sub`.
        # One rule per calling repository, because a pin is not covered by a
        # scope: any token holding `write` may create or repoint any pin that no
        # rule reserves, so a token minted for one repository could otherwise
        # move another repository's `main` pin. Each rule grants `write` to one
        # repository's CI identity and reserves that repository's pin namespace
        # — `<repository>-main-<system>`, e.g. `nix-fleet-main-aarch64-linux` —
        # for it alone. An admin token can still move them, which is the
        # operator's path. `rules` replaces the provider-level claims, so the
        # shared claims live inside each rule rather than beside them.
        oidc.providers.github = {
          issuer = "https://token.actions.githubusercontent.com";
          audience = "https://cache.shrublab.xyz";
          rules = map (repository: {
            boundClaims = ciClaims // {
              repository = [ "Shrub24/${repository}" ];
            };
            scopes = [ "write" ];
            pins = [ "${repository}-main-*" ];
          }) ciRepositories;
        };
        # The listen port is the private service policy's declaration, shared
        # with every publisher that dials it.
        httpAddr = lib.mkDefault "0.0.0.0:${toString niks3WritePort}";
      };

      # niks3 serves Prometheus metrics on the listener its API uses (`GET
      # /metrics`, unauthenticated like `/health`), so the host's own vmagent
      # collects them over loopback rather than the port being dialled from
      # elsewhere. The registration name is the scrape job name.
      services.telemetry.scrape = lib.mkIf hasTelemetryScrape {
        niks3 = {
          target = "127.0.0.1";
          port = niks3WritePort;
          metricsPath = "/metrics";
        };
      };
    };
}
