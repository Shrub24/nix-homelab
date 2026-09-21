set shell := ["bash", "-euo", "pipefail", "-c"]
set no-cd

# Local nix-fleet override.
#
# nix-fleet owns the pins this repository shares (nixpkgs, flake-parts,
# import-tree, sops-nix, niks3), so evaluating against a local nix-fleet
# checkout also exercises its locked shared baseline. Point at another checkout
# with `NIX_FLEET=/path/to/nix-fleet`; the default is the sibling dev checkout.
# `--override-input` applies to the single invocation: the committed flake.lock
# is not touched.
nf-eval host:
  #!/usr/bin/env bash
  set -euo pipefail
  root="$(git -C "$PWD" rev-parse --show-toplevel)"
  cd "$root"
  fleet="$(realpath -m "${NIX_FLEET:-$root/../nix/nix-fleet}")"
  nix eval --no-write-lock-file --override-input nix-fleet "path:$fleet" \
    ".#nixosConfigurations.{{host}}.config.system.build.toplevel.drvPath"

# Build a host against the local nix-fleet checkout.
nf-build host:
  #!/usr/bin/env bash
  set -euo pipefail
  root="$(git -C "$PWD" rev-parse --show-toplevel)"
  cd "$root"
  fleet="$(realpath -m "${NIX_FLEET:-$root/../nix/nix-fleet}")"
  nix build --no-link --no-write-lock-file --override-input nix-fleet "path:$fleet" \
    ".#nixosConfigurations.{{host}}.config.system.build.toplevel"

# Run the flake check against the local nix-fleet checkout.
nf-check:
  #!/usr/bin/env bash
  set -euo pipefail
  root="$(git -C "$PWD" rev-parse --show-toplevel)"
  cd "$root"
  fleet="$(realpath -m "${NIX_FLEET:-$root/../nix/nix-fleet}")"
  nix flake check --no-build --no-write-lock-file --override-input nix-fleet "path:$fleet" .#
