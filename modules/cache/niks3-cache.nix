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
      ciInstance = import ../../ci/instance.nix;
      s3 = globals.s3 or { };
      s3Host = builtins.replaceStrings [ "https://" "http://" ] [ "" "" ] (s3.endpoint or "");
      niks3WritePort = config.repo.web.catalog."niks3-write".endpoint.port;
      route = config.repo.web.catalog.nixbot;
      # The scrape binding exists only where nix-fleet's telemetry registry does.
      hasTelemetryScrape = lib.hasAttrByPath [ "services" "telemetry" "scrape" ] options;
    in
    {
      # The upstream server module is the consumer's seam, so this aspect imports it.
      imports = [
        inputs.niks3.nixosModules.niks3
        inputs.nix-fleet.modules.nixos.niks3-cache
      ];

      assertions = [
        {
          assertion = config.services.niks3-cache.cacheUrl == ciInstance.cacheUrl;
          message = "ci: instance.cacheUrl disagrees with the cache route";
        }
      ];

      services.niks3-cache = {
        s3 = {
          endpoint = lib.mkDefault s3Host;
          region = lib.mkDefault (s3.region or "");
        };
        secretFiles.host = lib.mkDefault ../../secrets/services/niks3.yaml;
        cacheUrl = lib.mkDefault "https://cache.${globals.domain}";
        gc.olderThan = "168h";
        nixbot = {
          issuer = route.publicUrl;
          owners = [ (import ../../policy/nixbot.nix).github.owner ];
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
