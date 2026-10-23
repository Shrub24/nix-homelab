# Operator development surface (perSystem): shell and formatter.
{
  perSystem =
    { pkgs, config, ... }:
    {
      devShells.default = pkgs.mkShell {
        packages = [
          pkgs.just
          pkgs.git
          pkgs.jq
          pkgs.yq-go
          pkgs.opentofu
          pkgs.prettier
          pkgs.shfmt
          pkgs.taplo
          pkgs.sops
          pkgs.age
          pkgs.nixos-anywhere
          pkgs.nix-output-monitor
          pkgs.nixfmt
          pkgs.ruff
          pkgs.statix
          pkgs.ssh-to-age
          pkgs.lefthook
          pkgs.deploy-rs
        ]
        ++ [
          config.packages.niks3
          config.packages.sops-bootstrap
          # The generated formatter: `treefmt` in this shell formats with the
          # configuration `modules/flake/treefmt.nix` declares, not a second file.
          config.treefmt.build.wrapper
        ];
        shellHook = ''
          unset PYTHONPATH
        '';
      };
    };
}
