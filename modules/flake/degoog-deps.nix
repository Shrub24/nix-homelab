# `pkgs/degoog/bun.nix` is generated data: a lock bump that is not accompanied
# by a regenerated expression builds the previous package set, so the generated
# file and the pin it derives from are compared instead of trusted. Both sides
# are formatted first, so `nix fmt` over the repository cannot invalidate it.
{
  inputs,
  lib,
  ...
}:
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks.check-degoog-bun-deps = pkgs.runCommandLocal "check-degoog-bun-deps" { } ''
        ${lib.getExe inputs.bun2nix.packages.${system}.default} \
          --lock-file ${inputs.degoog}/bun.lock --output-file bun.nix
        ${lib.getExe pkgs.nixfmt} bun.nix

        if ! ${lib.getExe pkgs.nixfmt} --check ${../../pkgs/degoog/bun.nix}; then
          echo "degoog: pkgs/degoog/bun.nix is not formatted" >&2
          exit 1
        fi

        if ! diff -u ${../../pkgs/degoog/bun.nix} bun.nix; then
          echo "degoog: pkgs/degoog/bun.nix does not match the pinned lockfile" >&2
          echo "regenerate with: nix run .#update-packages -- degoog" >&2
          exit 1
        fi

        touch $out
      '';
    };
}
