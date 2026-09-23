# AI domain knowledge: hindsight, agent memory on home-forge. The aspect owner
# supplies the enablement that selection means; the options and runtime body
# live in the sibling contributor ./hindsight/service.nix, which publishes the
# same aspect name.
{
  flake.modules.nixos.hindsight = {
    # Selecting the deployment aspect is the only enablement.
    services.hindsight.enable = true;
  };
}
