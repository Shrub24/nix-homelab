# Formatting, declared once: `nix fmt` runs this configuration, `just fmt` does
# through the devShell wrapper, and `checks.<system>.treefmt` is the gate the
# fleet's validator builds. Settings live here rather than in a treefmt.toml
# because treefmt-nix renders the config from this module.
#
# The formatters are declared as raw `settings.formatter` entries rather than
# through `programs.*`: the programs carry their own option sets, and these are
# the exact invocations this repository's tree was formatted with.
{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem =
    { pkgs, ... }:
    {
      treefmt = {
        projectRootFile = "flake.nix";

        settings.global.excludes = [
          ".jj/**"
          ".pi/**"
          "secrets/**"
          "generated/**"
          "result"
          "result-*"
          "flake.lock"
          ".terraform.lock.hcl"
        ];

        settings.formatter = {
          nix = {
            command = "${pkgs.nixfmt}/bin/nixfmt";
            includes = [ "*.nix" ];
          };
          yaml = {
            command = "${pkgs.prettier}/bin/prettier";
            options = [
              "--parser"
              "yaml"
            ];
            includes = [
              "*.yaml"
              "*.yml"
            ];
          };
          toml = {
            command = "${pkgs.taplo}/bin/taplo";
            options = [ "format" ];
            includes = [ "*.toml" ];
          };
          markdown = {
            command = "${pkgs.prettier}/bin/prettier";
            options = [
              "--parser"
              "markdown"
            ];
            includes = [ "*.md" ];
          };
          shell = {
            command = "${pkgs.shfmt}/bin/shfmt";
            includes = [
              "*.sh"
              "*.bash"
            ];
          };
          json = {
            command = "${pkgs.prettier}/bin/prettier";
            options = [
              "--parser"
              "json"
            ];
            includes = [ "*.json" ];
          };
          python = {
            command = "${pkgs.ruff}/bin/ruff";
            options = [ "format" ];
            includes = [ "*.py" ];
          };
          terraform = {
            command = "${pkgs.opentofu}/bin/tofu";
            options = [ "fmt" ];
            includes = [
              "*.tf"
              "*.tfvars"
            ];
          };
        };
      };
    };
}
