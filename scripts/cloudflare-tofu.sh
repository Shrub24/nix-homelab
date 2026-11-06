#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
TF_DIR="$ROOT_DIR/opentofu/cloudflare"
FOUNDATION_DIR="$TF_DIR/foundation"
FOUNDATION_KEY="opentofu/cloudflare/foundation.tfstate"

COMMAND=${1:?Expected init or apply}
shift
case "$COMMAND" in
  init | apply) ;;
  *) echo "Expected init or apply" >&2; exit 2 ;;
esac

FOUNDATION=false
SYNC=false
ARGS=()
while (( $# )); do
  case $1 in
    --foundation) FOUNDATION=true ;;
    --sync) SYNC=true ;;
    --) ARGS+=("$@"); break ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done

if [[ $SYNC == true ]]; then just tofu::sync; fi
just tofu::_runtime

init() {
  local dir=$1
  shift
  local backend=(-backend-config="$TF_DIR/backend.hcl")
  if [[ $dir == "$FOUNDATION_DIR" ]]; then
    backend+=(-backend-config="key=$FOUNDATION_KEY")
  fi
  tofu -chdir="$dir" init "${backend[@]}" "$@"
}

ensure_initialized() {
  if [[ ! -f $1/.terraform/terraform.tfstate ]]; then init "$1"; fi
}

DIR=$TF_DIR
if [[ $FOUNDATION == true ]]; then DIR=$FOUNDATION_DIR; fi
if [[ $COMMAND == init ]]; then
  init "$DIR" "${ARGS[@]}"
  exit
fi

ensure_initialized "$TF_DIR"
if [[ $FOUNDATION == true ]]; then ensure_initialized "$FOUNDATION_DIR"; fi
# Neither root may apply while service publication still owns the combined state.
addresses=$(tofu -chdir="$TF_DIR" state list)
while IFS= read -r address; do
  case "$address" in
    "" | cloudflare_dns_record.service\[* | cloudflare_zero_trust_access_application.service\[*) ;;
    *)
      echo 'Split the combined Cloudflare state before applying either root; see docs/runbooks/cloudflare-split.md.' >&2
      exit 1
      ;;
  esac
done <<< "$addresses"

if [[ $FOUNDATION == false ]]; then
  ensure_initialized "$FOUNDATION_DIR"
  refs=$(mktemp "$TF_DIR/.foundation-refs.XXXXXX")
  trap 'rm -f "$refs"' EXIT
  # This reads the foundation state, not the Cloudflare objects it owns.
  if ! tofu -chdir="$FOUNDATION_DIR" output -json service_access | jq '{foundation_access: .}' > "$refs"; then
    echo 'Apply foundation after the state split before publishing services (just tofu::apply --foundation).' >&2
    exit 1
  fi
  mv "$refs" "$TF_DIR/foundation.auto.tfvars.json"
fi

tofu -chdir="$DIR" apply "${ARGS[@]}"
