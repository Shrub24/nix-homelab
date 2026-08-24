set shell := ["bash", "-euo", "pipefail", "-c"]
set no-cd

# Diagnostic only: derive the age recipient from a live ssh-keyscan result for
# preview. A keyscan result is NOT verified against the provider-console
# fingerprint and must never be persisted. Persist a recipient only via
# `from-key` after the supplied key matches the console fingerprint.
[arg("port", long)]
get host port="22":
  @HOST="{{host}}"; PORT="{{port}}"; \
  KEY_LINE="$(ssh-keyscan -p "$PORT" -t ed25519 "$HOST" 2>/dev/null | awk '/ssh-ed25519/ {print $0; exit}')"; \
  if [[ -z "$KEY_LINE" ]]; then echo "Error: cannot reach $HOST:$PORT"; exit 1; fi; \
  AGE_RECIPIENT="$(printf '%s\n' "$KEY_LINE" | nix shell nixpkgs#ssh-to-age --command ssh-to-age)"; \
  echo "${AGE_RECIPIENT}"; \
  echo "(diagnostic preview only — verify this recipient against the provider-console fingerprint before use)"; \
  echo "(to persist, run: just host-age from-key '<console-verified ssh-ed25519 ...>' key_alias=<host>_age update=true)"

# Safe persist path: the operator supplies the host public key and must first
# verify it matches the provider-console fingerprint (e.g. via
# scripts/ssh-known-hosts.sh verify or ssh-keygen -lf). Never paste an
# unverified ssh-keyscan result here; the anchor becomes the host's SOPS
# decryption identity for the lifetime of its ciphertext.
[arg("key_alias", long)]
[arg("update", long)]
from-key pubkey key_alias="host_generic_age" update="false":
  @KEY_ALIAS="{{key_alias}}"; UPDATE="{{update}}"; \
  AGE_RECIPIENT="$(printf '%s\n' "{{pubkey}}" | nix shell nixpkgs#ssh-to-age --command ssh-to-age)"; \
  if [[ "$UPDATE" == "true" ]]; then \
    python3 scripts/update-age-anchor.py .sops.yaml "$KEY_ALIAS" "$AGE_RECIPIENT"; \
    echo "Updated .sops.yaml anchor &${KEY_ALIAS} => ${AGE_RECIPIENT}"; \
  else \
    echo "${AGE_RECIPIENT}"; \
    echo "(preview — re-run with update=true to persist)"; \
  fi
