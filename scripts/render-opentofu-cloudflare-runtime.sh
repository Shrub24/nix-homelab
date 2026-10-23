#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SECRET_FILE="${ROOT_DIR}/secrets/opentofu/cloudflare.yaml"
OIDC_SECRET_FILE="${ROOT_DIR}/secrets/opentofu/oidc.yaml"
TOFU_DIR="${ROOT_DIR}/opentofu/cloudflare"
SECRETS_VARS_FILE="${TOFU_DIR}/secrets.auto.tfvars"

if [[ ! -f "${SECRET_FILE}" ]]; then
  echo "Missing ${SECRET_FILE}. Create/encrypt it first." >&2
  exit 1
fi

tmp_json="$(mktemp)"
tmp_oidc_json="$(mktemp)"
cleanup() {
  rm -f "${tmp_json}"
  rm -f "${tmp_oidc_json}"
}
trap cleanup EXIT

sops --decrypt --output-type json "${SECRET_FILE}" > "${tmp_json}"
sops --decrypt --output-type json "${OIDC_SECRET_FILE}" > "${tmp_oidc_json}"

python3 - <<'PY' "${tmp_json}" "${tmp_oidc_json}" "${SECRETS_VARS_FILE}"
import json
import pathlib
import sys

src = pathlib.Path(sys.argv[1])
oidc_src = pathlib.Path(sys.argv[2])
secrets_vars_path = pathlib.Path(sys.argv[3])

data = json.loads(src.read_text(encoding="utf-8"))
oidc_data = json.loads(oidc_src.read_text(encoding="utf-8"))
cf = data.get("cloudflare", {})
cloudflare_access = oidc_data.get("cloudflare-access", {})

required_secret_var_keys = [
    "cloudflare_api_token",
    "cloudflare_account_id",
    "cloudflare_zone_id",
    "edge_record_target",
    "origin_record_content",
    "admin_email",
]

missing_vars = [k for k in required_secret_var_keys if not cf.get(k)]

if missing_vars:
    details = []
    if missing_vars:
        details.append(f"cloudflare.{', '.join(missing_vars)}")
    raise SystemExit("Missing required secrets: " + "; ".join(details))

secret_tfvars = {
    "cloudflare_api_token": cf["cloudflare_api_token"],
    "cloudflare_account_id": cf["cloudflare_account_id"],
    "cloudflare_zone_id": cf["cloudflare_zone_id"],
    "edge_record_target": cf["edge_record_target"],
    "origin_record_content": cf["origin_record_content"],
    "admin_email": cf["admin_email"],
}

optional_secret_tfvars = [
    ("idp_client_id", "cloudflare-access"),
    ("idp_client_secret", cloudflare_access.get("client_secret")),
]

for key, value in optional_secret_tfvars:
    if value is not None and str(value).strip() != "":
        secret_tfvars[key] = value

tfvars_lines = []
for key, value in secret_tfvars.items():
    tfvars_lines.append(f"{key} = {json.dumps(value)}")

secrets_vars_path.write_text("\n".join(tfvars_lines) + "\n", encoding="utf-8")
PY

echo "Rendered ${SECRETS_VARS_FILE}"
