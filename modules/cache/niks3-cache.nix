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
        # The listen port is the private service policy's declaration, shared
        # with every publisher that dials it.
        httpAddr = lib.mkDefault "0.0.0.0:${toString config.repo.web.catalog."niks3-write".endpoint.port}";
      };
    };
}
