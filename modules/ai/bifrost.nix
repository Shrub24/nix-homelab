# AI domain: bifrost, the fleet's OpenAI-compatible gateway on oci-melb-1.
# The aspect owner supplies the enablement that selection means; the options
# and runtime body live in the sibling contributor ./bifrost/service.nix,
# which publishes the same aspect name.
{
  flake.modules.nixos.bifrost = {
    # Selecting the deployment aspect is the only enablement.
    services.bifrost.enable = true;
  };
}
