# AI domain knowledge: degooog, the private search front end on home-forge.
# The aspect owner supplies the enablement and the upstream import that
# selection means — the upstream NixOS module owns `services.degoog.*` runtime
# options — while the options and runtime body contributions live in the
# sibling contributor ./degoog/service.nix, which publishes the same aspect
# name. The input is declared here, beside the capability that needs it.
{ inputs, ... }:
{
  flake-file.inputs.degoog = {
    url = "github:degoog-org/degoog";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.flake-parts.follows = "flake-parts";
  };

  flake.modules.nixos.degoog = {
    imports = [ inputs.degoog.nixosModules.default ];

    # Selecting the deployment aspect is the only enablement.
    services.degoog.enable = true;
  };
}
