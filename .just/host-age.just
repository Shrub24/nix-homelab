set shell := ["bash", "-euo", "pipefail", "-c"]
set no-cd

[arg("port", long)]
[arg("key_alias", long)]
[arg("update", long)]
get host port="22" key_alias="host_generic_age" update="false":
  @HOST="{{host}}"; PORT="{{port}}"; KEY_ALIAS="{{key_alias}}"; UPDATE="{{update}}"; \
  KEY_LINE="$(ssh-keyscan -p "$PORT" -t ed25519 "$HOST" 2>/dev/null | awk '/ssh-ed25519/ {print $0; exit}')"; \
  if [[ -z "$KEY_LINE" ]]; then echo "Error: cannot reach $HOST:$PORT"; exit 1; fi; \
  AGE_RECIPIENT="$(printf '%s\n' "$KEY_LINE" | nix shell nixpkgs#ssh-to-age --command ssh-to-age)"; \
  if [[ "$UPDATE" == "true" ]]; then \
    python3 -c "import re, sys; path, alias, recipient = sys.argv[1:4]; text = open(path, 'r', encoding='utf-8').read(); pattern = rf'^(\\s*-\\s*&{re.escape(alias)}\\s+)age1[0-9a-z]+\\s*$'; new, count = re.subn(pattern, rf'\\1{recipient}', text, count=1, flags=re.MULTILINE); open(path, 'w', encoding='utf-8').write(new)" .sops.yaml "$KEY_ALIAS" "$AGE_RECIPIENT"; \
    echo "Updated .sops.yaml anchor &${KEY_ALIAS} => ${AGE_RECIPIENT}"; \
  else \
    echo "${AGE_RECIPIENT}"; \
    echo "(preview — re-run with update=true to persist)"; \
  fi

[arg("key_alias", long)]
[arg("update", long)]
from-key pubkey key_alias="host_generic_age" update="false":
  @KEY_ALIAS="{{key_alias}}"; UPDATE="{{update}}"; \
  AGE_RECIPIENT="$(printf '%s\n' "{{pubkey}}" | nix shell nixpkgs#ssh-to-age --command ssh-to-age)"; \
  if [[ "$UPDATE" == "true" ]]; then \
    python3 -c "import re, sys; path, alias, recipient = sys.argv[1:4]; text = open(path, 'r', encoding='utf-8').read(); pattern = rf'^(\\s*-\\s*&{re.escape(alias)}\\s+)age1[0-9a-z]+\\s*$'; new, count = re.subn(pattern, rf'\\1{recipient}', text, count=1, flags=re.MULTILINE); open(path, 'w', encoding='utf-8').write(new)" .sops.yaml "$KEY_ALIAS" "$AGE_RECIPIENT"; \
    echo "Updated .sops.yaml anchor &${KEY_ALIAS} => ${AGE_RECIPIENT}"; \
  else \
    echo "${AGE_RECIPIENT}"; \
    echo "(preview — re-run with update=true to persist)"; \
  fi
