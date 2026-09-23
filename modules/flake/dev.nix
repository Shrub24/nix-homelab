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
          pkgs.treefmt
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
        ++ [ config.packages.niks3 ];
        shellHook = ''
          unset PYTHONPATH
        '';
      };

      formatter = pkgs.nixfmt;
    };
}
