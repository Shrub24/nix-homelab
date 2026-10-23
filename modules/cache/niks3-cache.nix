# Niks3 cache server: nix-fleet owns the mechanism; this contributor supplies the fleet's S3 coordinates and public URL.
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
      s3Host = builtins.replaceStrings [ "https://" "http://" ] [ "" "" ] (s3.endpoint or "");
      # Shared claims read the same in both GitHub subject forms; the workflow is bound per rule, because publish and pin are different powers.
      ciClaims = workflow: {
        repository_owner_id = [ "20262061" ];
        ref = [ "refs/heads/main" ];
        job_workflow_ref = [ "Shrub24/nix-fleet/.github/workflows/${workflow}@*" ];
      };
      # One reserved pin namespace per repository.
      ciRepositories = [
        "nix-fleet"
        "nix-homelab"
        "nix-dotfiles"
        "memex"
        "Pi-Bolt.nix"
        "agent-radar"
      ];
      niks3WritePort = config.repo.web.catalog."niks3-write".endpoint.port;
      # The scrape binding exists only where nix-fleet's telemetry registry does.
      hasTelemetryScrape = lib.hasAttrByPath [ "services" "telemetry" "scrape" ] options;
    in
    {
      # The upstream server module is the consumer's seam, so this aspect imports it.
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
        # CI federation: GitHub OIDC tokens push, R2 serves reads. Claims are bound, not `sub`, and
        # one rule per repository reserves its pin namespace because a pin is not scoped.
        oidc.providers.github = {
          issuer = "https://token.actions.githubusercontent.com";
          audience = "https://cache.shrublab.xyz";
          rules = lib.concatMap (
            repository:
            let
              bound = claims: {
                boundClaims = claims // {
                  repository = [ "Shrub24/${repository}" ];
                };
              };
            in
            [
              (
                bound (ciClaims "build-push-cache.yml")
                // {
                  scopes = [ "write" ];
                  pins = [ ];
                }
              )
              # Pins are gated by name, not scope: a pins-only rule would be rejected, so each rule keeps `write`.
              (
                bound (ciClaims "pin-cache.yml")
                // {
                  scopes = [ "write" ];
                  pins = [ "${repository}-main-*" ];
                }
              )
            ]
          ) ciRepositories;
        };
        # Listen port comes from the private service policy, shared with every publisher.
        httpAddr = lib.mkDefault "0.0.0.0:${toString niks3WritePort}";
      };

      # /metrics is unauthenticated like /health; the host's vmagent scrapes it over loopback.
      services.telemetry.scrape = lib.mkIf hasTelemetryScrape {
        niks3 = {
          target = "127.0.0.1";
          port = niks3WritePort;
          metricsPath = "/metrics";
        };
      };
    };
}
