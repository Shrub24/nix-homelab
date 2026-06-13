set shell := ["bash", "-euo", "pipefail", "-c"]
set no-cd

# Regenerate nvfetcher-managed non-flake source metadata.
refresh:
    nix run nixpkgs#nvfetcher -- -o pkgs/_sources
