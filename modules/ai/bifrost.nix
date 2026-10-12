# AI domain: bifrost, the fleet's OpenAI-compatible gateway, placed on the hosts
# whose workloads call it (oci-melb-1 and home-forge).
#
# The aspect owner supplies the deployment mechanism: importing nix-fleet's
# gateway service is what places it — there is no `enable` flag, and selection
# is the only enablement. The fleet's conventions for this repository (settings,
# plugins, secrets, exposure, backups) live in the sibling contributor
# ./bifrost/service.nix, which publishes the same aspect name.
#
# The listen port is the canonical cross-fleet record's (nix-fleet's service
# inventory), resolved here because the options file sits one level deeper than
# the scaffold contract lets a flake argument reach. The definition is weak, so
# a host may still override it.
{
  config,
  inputs,
  lib,
  ...
}:
let
  canonicalPort =
    (inputs.nix-fleet.lib.serviceEndpoints.resolveEndpoint config.fleet {
      service = "bifrost";
      endpoint = "embeddings";
      via = "tailnet";
    }).port;

  # The gateway's own spans are an enrolled AI producer's, so they belong on
  # the AI lane rather than the general ingress: `ai-otlp` is the canonical
  # cross-fleet record for that route, and resolving it here means a route move
  # is an upstream edit plus a relock, never a local one.
  otlpGateway =
    (inputs.nix-fleet.lib.serviceEndpoints.resolveEndpoint config.fleet {
      service = "otel-collector";
      endpoint = "ai-otlp";
      via = "tailnet";
    }).url;
in
{
  flake.modules.nixos.bifrost = {
    imports = [ inputs.nix-fleet.modules.nixos.bifrost ];

    services.bifrost.port = lib.mkDefault canonicalPort;
    services.bifrost.plugins.otel.config.collector_url = lib.mkDefault "${otlpGateway}/v1/traces";
  };
}
