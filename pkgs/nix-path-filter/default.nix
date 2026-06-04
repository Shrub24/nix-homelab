{ writeShellApplication, nix, jq }:

writeShellApplication {
  name = "nix-path-filter";
  runtimeInputs = [ nix jq ];

  text = ''
    set -euo pipefail

    EXCLUDE_PATTERN="^(cache\\.nixos\\.org|nix-community\\.cachix\\.org)-"

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --exclude)
          EXCLUDE_PATTERN="^($(echo "$2" | tr ' ' '|'))-"
          shift 2
          ;;
        --no-recursive)
          shift
          ;;
        *)
          break
          ;;
      esac
    done

    if [ $# -eq 0 ]; then
      echo "Usage: nix-path-filter [--exclude 'key1 key2'] <store-path>..." >&2
      exit 1
    fi

    PATH_INFO_FLAGS="--recursive --json --sigs"

    # shellcheck disable=SC2086 # word splitting is intentional for multiple flags
    nix path-info $PATH_INFO_FLAGS "$@" \
      | jq -r --arg re "$EXCLUDE_PATTERN" \
        '.[] | select(.sigs | any(test($re)) | not) | .path'
  '';
}
