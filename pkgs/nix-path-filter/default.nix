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
          if [[ $# -lt 2 ]]; then
            echo "Missing value for --exclude" >&2
            exit 1
          fi
          EXCLUDE_PATTERN="^($(echo "$2" | tr ' ' '|'))-"
          shift 2
          ;;
        --)
          shift
          break
          ;;
        -*)
          echo "Unknown option: $1" >&2
          exit 1
          ;;
        *)
          break
          ;;
      esac
    done

    if [ $# -eq 0 ]; then
      mapfile -t STORE_PATHS
      if [ "''${#STORE_PATHS[@]}" -eq 0 ]; then
        echo "Usage: nix-path-filter [--exclude 'key1 key2'] <store-path>..." >&2
        exit 1
      fi
      set -- "''${STORE_PATHS[@]}"
    fi

    PATH_INFO_FLAGS="--recursive --json --json-format 2 --sigs"

    # shellcheck disable=SC2086 # word splitting is intentional for multiple flags
    nix path-info $PATH_INFO_FLAGS "$@" \
      | jq -r --arg re "$EXCLUDE_PATTERN" \
        '.storeDir as $storeDir | .info | to_entries[] | select((.value.signatures // []) | any(test($re)) | not) | "\($storeDir)/\(.key)"'
  '';
}
