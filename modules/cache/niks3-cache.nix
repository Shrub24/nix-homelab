# Niks3 cache-server aspect. nix-fleet owns the server mechanism (the fail-closed
# option surface, the upstream niks3 service wiring, the secret registrations);
# this contributor supplies the fleet's deployment policy — the S3 coordinates
# from policy/globals.nix and the public cache URL — and leaves the secret-file
# bindings to the host that owns them.
{ inputs, ... }:
{
  flake.modules.nixos.niks3-cache =
    { config, lib, ... }:
    let
      globals = import ../../policy/globals.nix;
      s3 = globals.s3 or { };
      # niks3 derives TLS from useSSL, so the endpoint carries no protocol.
      s3Host = builtins.replaceStrings [ "https://" "http://" ] [ "" "" ] (s3.endpoint or "");
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
        # Branch-only subjects keep refs/pull/* out of the cache.
        oidc.providers.github = {
          issuer = "https://token.actions.githubusercontent.com";
          audience = "https://cache.shrublab.xyz";
          boundClaims.repository_owner = [ "Shrub24" ];
          boundSubject = [ "repo:Shrub24/*:ref:refs/heads/*" ];
          scopes = [ "write" ];
        };
        # The listen port is the private service policy's declaration, shared
        # with every publisher that dials it.
        httpAddr = lib.mkDefault "0.0.0.0:${toString config.repo.web.catalog."niks3-write".endpoint.port}";
      };
    };
}
