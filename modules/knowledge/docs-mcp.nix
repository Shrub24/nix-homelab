# AI domain knowledge: docs-mcp, the grounded documentation index on
# home-forge. The aspect owner supplies the enablement that selection means;
# the options and runtime body live in the sibling contributor
# ./docs-mcp/service.nix, which publishes the same aspect name.
{
  flake.modules.nixos.docs-mcp = {
    # Selecting the deployment aspect is the only enablement.
    services.docs-mcp.enable = true;
  };
}
