#!/usr/bin/env bash
set -euo pipefail
# Contract test for the Kanidm restore helper (modules/services/admin/kanidm.nix).
# Renders the exact writeShellScript body from the module source, exercises the
# guard logic and the fail-closed offline verification gate with a stubbed
# kanidmd, then runs a real restore/verify against a scratch database when the
# pinned kanidmd binary is already built. No remote operations.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

MOD=modules/services/admin/kanidm.nix

# --- source contract: operator-invoked only, never auto/timer started ---
UNIT_BLOCK="$(sed -n '/systemd.services."kanidm-restore@"/,/};/p' "$MOD")"
if grep -q 'wantedBy' <<<"$UNIT_BLOCK"; then
  echo "kanidm-restore: unit must not declare wantedBy (operator-invoked only)" >&2
  exit 1
fi
if grep -q 'systemd.timers."kanidm-restore' "$MOD"; then
  echo "kanidm-restore: must not define a timer" >&2
  exit 1
fi
if ! grep -q 'ExecStart = "${restoreScript} %I"' "$MOD"; then
  echo "kanidm-restore: unit must pass the operator-provided artifact path via %I" >&2
  exit 1
fi
if ! grep -q 'database restore' "$MOD" || ! grep -q 'database verify' "$MOD"; then
  echo "kanidm-restore: script must run restore then offline verify" >&2
  exit 1
fi
if ! grep -q 'chown -R kanidm:kanidm' "$MOD"; then
  echo "kanidm-restore: script must repair database ownership for the kanidm service" >&2
  exit 1
fi
if ! grep -q 'Start kanidm.service manually when ready' "$MOD"; then
  echo "kanidm-restore: script must state that Kanidm start remains manual" >&2
  exit 1
fi

# --- render the exact script body from the module source ---
KANIDMD="$(nix eval --no-write-lock-file --raw 'path:.#nixosConfigurations.la-admin-1.config.services.kanidm.package.outPath')/bin/kanidmd"
CONFIG_PATH="$WORK/server.toml"
DB_PATH="$WORK/kanidm.db"
OWNER="$(id -un):$(id -gn)"

render_script() {
  # $1 = rendered script path; $2 = target owner; $3 = systemctl stub (optional); $4 = chown stub (optional)
  # RM is the `rm` replacement (defaults to the real rm); a failing RM stub
  # exercises the cleanup-failure gate.
  OWNER="$2" WORK="$WORK" CONFIG_PATH="$CONFIG_PATH" DB_PATH="$DB_PATH" \
  KANIDMD="$KANIDMD" SYSTL="${3:-systemctl}" CHOWN="${4:-chown}" RM="${RM_STUB:-rm}" python3 - "$MOD" "$1" <<'PYEOF'
import os, re, sys
src = open(sys.argv[1]).read()
m = re.search(r'restoreScript = pkgs\.writeShellScript "kanidm-restore" \'\'\n(.*?)\'\';\nin', src, re.S)
if not m:
    sys.exit("kanidm-restore: writeShellScript block not found in " + sys.argv[1])
script = m.group(1)
script = script.replace("''${", "${")  # Nix escape for a literal bash ${...}
script = script.replace("${pkgs.systemd}/bin/systemctl", os.environ["SYSTL"])
script = script.replace("${pkgs.coreutils}/bin/rm", os.environ["RM"])
script = script.replace("${pkgs.coreutils}/bin/", "")
script = script.replace("${pkgs.gnugrep}/bin/", "")
script = script.replace("${pkgs.gnused}/bin/", "")
script = script.replace("${config.services.kanidm.server.settings.db_path}", os.environ["DB_PATH"])
script = script.replace("-c /etc/kanidm/server.toml", "-c " + os.environ["CONFIG_PATH"])
script = script.replace("${kanidmd}", os.environ["KANIDMD"])
script = script.replace("kanidm:kanidm", os.environ["OWNER"])
script = script.replace("chown -R " + os.environ["OWNER"], os.environ["CHOWN"] + " -R " + os.environ["OWNER"])
open(sys.argv[2], "w").write(script)
PYEOF
  chmod +x "$1"
}
RM_STUB="rm"

RENDERED="$WORK/kanidm-restore.sh"
render_script "$RENDERED" "$OWNER"
bash -n "$RENDERED"

# --- guard logic (no binary needed) ---
set +e
"$RENDERED" >/dev/null 2>&1; rc=$?
set -e
if [[ $rc -ne 2 ]]; then echo "kanidm-restore: missing artifact path must exit 2 (got $rc)" >&2; exit 1; fi

set +e
"$RENDERED" "$WORK/backup-test.json" >/dev/null 2>&1; rc=$?
set -e
if [[ $rc -ne 2 ]]; then echo "kanidm-restore: non-json.gz artifact must exit 2 (got $rc)" >&2; exit 1; fi

set +e
"$RENDERED" "$WORK/missing.json.gz" >/dev/null 2>&1; rc=$?
set -e
if [[ $rc -ne 2 ]]; then echo "kanidm-restore: missing artifact file must exit 2 (got $rc)" >&2; exit 1; fi

# --- active-service refusal (systemctl stub always reports active) ---
# A real placeholder artifact is required: the missing-file guard runs before
# the active-service guard.
touch "$WORK/backup-test.json.gz"
SYSTL_STUB="$WORK/systemctl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SYSTL_STUB"
chmod +x "$SYSTL_STUB"
REFUSAL="$WORK/kanidm-restore-refusal.sh"
render_script "$REFUSAL" "$OWNER" "$SYSTL_STUB"
set +e
OUT="$( "$REFUSAL" "$WORK/backup-test.json.gz" 2>&1 )"; rc=$?
set -e
if [[ $rc -ne 1 ]] || ! grep -q 'refusing to restore while kanidm.service is active' <<<"$OUT"; then
  echo "kanidm-restore: active kanidm.service must be refused (exit 1) with a clear message" >&2
  echo "$OUT" >&2
  exit 1
fi

# --- fail-closed offline verification gate (stubbed kanidmd) ---
# The helper is unconditionally fail-closed: every nonzero offline verification
# result is fatal before chown or the manual-start message; there is no
# version-pinned acceptance path. Verify fixtures model the real tracing-forest
# envelope as compiled by Kanidm: root-level events carry the nil-UUID prefix,
# a `{:<8} ` level field, and the `🚨 [error]:` tag; `Verification passed!`
# is an eprintln; `Logging filter initialized: ...` is the pre-pipeline
# eprintln. Routine startup INFO, permission WARN, and reindex/progress
# diagnostics (observed on LA) carry no error marker and are permitted ONLY on
# the clean path (exit 0 with "Verification passed"). TMPDIR points at a scratch
# dir so tests prove the helper's temporary log is removed on every exit.
make_stub() {
  cat > "$1" <<'STUBEOF'
#!/usr/bin/env bash
# Stub of the pinned kanidmd for restore-helper contract scenarios. The
# SCENARIO_DIR env selects the fixture files for this scenario.
if [[ "${1:-}" == "-c" ]]; then shift 2; fi
case "$*" in
  "database restore "*) printf '%s\n' 'INFO     ｉ [info]: Running in restore mode ...'; exit 0 ;;
  "database verify")
    cat "$SCENARIO_DIR/verify.txt" 2>/dev/null || true
    exit "$(cat "$SCENARIO_DIR/verify.rc" 2>/dev/null || echo 0)"
    ;;
  *) exit 9 ;;
esac
STUBEOF
  chmod +x "$1"
}
STUB="$WORK/kanidmd-stub"
make_stub "$STUB"
SYSTL_INACTIVE="$WORK/systemctl-inactive"
printf '#!/usr/bin/env bash\nexit 1\n' > "$SYSTL_INACTIVE"
chmod +x "$SYSTL_INACTIVE"
CHOWN_STUB="$WORK/chown"
printf '#!/usr/bin/env bash\necho "$@" > "%s/chown.log"\n' "$WORK" > "$CHOWN_STUB"
chmod +x "$CHOWN_STUB"
SCEN="$WORK/scenarios"
mkdir -p "$SCEN"
# The helper's `mktemp` honours TMPDIR; keep the scratch dir local and assert
# it is empty after every stub scenario (proves the EXIT trap removes the
# temporary verifier log on success and on every failure path).
export TMPDIR="$WORK/tmp"
mkdir -p "$TMPDIR"

make_scenario() { # $1=name $2=verify rc; caller writes verify.txt
  local dir="$SCEN/$1"
  mkdir -p "$dir"
  printf '%s\n' "$2" > "$dir/verify.rc"
}

stub_scenario() { # $1=scenario name; renders and runs the helper under the stub
  local name="$1" out="$WORK/stub-$1.sh"
  rm -f "$WORK/chown.log"
  KANIDMD="$STUB" render_script "$out" "$OWNER" "$SYSTL_INACTIVE" "$CHOWN_STUB"
  set +e
  SCENARIO_DIR="$SCEN/$name" "$out" "$WORK/backup-test.json.gz" >"$out.log" 2>&1
  STUB_RC=$?
  set -e
  if [[ -n "$(ls -A "$TMPDIR" 2>/dev/null)" ]]; then
    echo "kanidm-restore: temporary verifier log not removed after $name" >&2
    ls -A "$TMPDIR" >&2 || true
    exit 1
  fi
}

# Rejected scenarios must fail before ownership repair (no chown.log) and
# before the manual-start message, with the expected fatal message and (when
# the failing path surfaces it) the verifier's output for diagnosis.
reject_scenario() { # $1=scenario name $2=expected fatal message fragment $3=surfaced fixture line (grep -F, optional)
  local name="$1" fragment="$2" surfaced="${3:-}" log="$WORK/stub-$1.sh.log"
  if [[ $STUB_RC -eq 0 ]] || ! grep -q "$fragment" "$log" || grep -q 'Start kanidm.service manually when ready' "$log" || [[ -e "$WORK/chown.log" ]]; then
    echo "kanidm-restore: $name must be rejected before ownership repair or manual start" >&2
    cat "$log" >&2
    exit 1
  fi
  if [[ -n "$surfaced" ]] && ! grep -qF -- "$surfaced" "$log"; then
    echo "kanidm-restore: $name must surface the verifier output" >&2
    cat "$log" >&2
    exit 1
  fi
}

# Clean verify: accepted with the verifier's output surfaced.
make_scenario clean 0
cat > "$SCEN/clean/verify.txt" <<'EOF'
Logging filter initialized: "kanidm_core::https::trace=info,tonic=warn,h2=warn"
00000000-0000-0000-0000-000000000000 INFO     ｉ [info]: Running in db verification mode ...
Verification passed!
EOF
stub_scenario clean
if [[ $STUB_RC -ne 0 ]] || ! grep -q 'Verification passed' "$WORK/stub-clean.sh.log" || ! grep -q 'Start kanidm.service manually when ready' "$WORK/stub-clean.sh.log" || ! grep -q -- "-R $OWNER $WORK" "$WORK/chown.log"; then
  echo "kanidm-restore: clean offline verify must pass through and proceed to ownership repair" >&2
  cat "$WORK/stub-clean.sh.log" >&2
  exit 1
fi

# rc=0 with "Verification passed!" alongside an error-bearing line: the clean
# path must not short-circuit marker parsing; rejected before chown/manual-start
# (the EXIT trap still removes the temporary verifier log).
make_scenario cleanwitherror 0
cat > "$SCEN/cleanwitherror/verify.txt" <<'EOF'
Logging filter initialized: "kanidm_core::https::trace=info,tonic=warn,h2=warn"
00000000-0000-0000-0000-000000000000 INFO     ｉ [info]: Running in db verification mode ...
Verification passed!
00000000-0000-0000-0000-000000000000 ERROR    🚨 [error]: Err(OtherError("x"))
EOF
stub_scenario cleanwitherror
reject_scenario cleanwitherror 'alongside' 'Err(OtherError("x"))'

# Setup-failure shape: a zero exit without "Verification passed" is treated as
# fatal (the pinned binary exits 0 only together with "Verification passed"),
# so the helper never trusts an inconsistent rc/output pair, including one that
# also carries findings.
make_scenario nofinding 0
cat > "$SCEN/nofinding/verify.txt" <<'EOF'
Logging filter initialized: "kanidm_core::https::trace=info,tonic=warn,h2=warn"
00000000-0000-0000-0000-000000000000 ERROR    🚨 [error]: Failed to finish verification
EOF
stub_scenario nofinding
reject_scenario nofinding 'exited 0 without'

# Plain nonzero verify with only routine non-error diagnostics: fatal.
make_scenario failedplain 1
cat > "$SCEN/failedplain/verify.txt" <<'EOF'
Logging filter initialized: "kanidm_core::https::trace=info,tonic=warn,h2=warn"
00000000-0000-0000-0000-000000000000 INFO     ｉ [info]: Running in db verification mode ...
00000000-0000-0000-0000-000000000000 WARN     🚧 [warn]: The database file /var/lib/kanidm/kanidm.db has weak permissions: 0644
EOF
stub_scenario failedplain
reject_scenario failedplain 'offline verify failed' 'Running in db verification mode'

# A RefintNotUpheld finding on a nonzero verify: fatal. There is no acceptance
# path for dangling-reference findings; the verifier output is surfaced for
# diagnosis.
make_scenario refintwitherror 1
cat > "$SCEN/refintwitherror/verify.txt" <<'EOF'
Logging filter initialized: "kanidm_core::https::trace=info,tonic=warn,h2=warn"
00000000-0000-0000-0000-000000000000 INFO     ｉ [info]: Running in db verification mode ...
00000000-0000-0000-0000-000000000000 ERROR    🚨 [error]: Err(RefintNotUpheld(319))
EOF
stub_scenario refintwitherror
reject_scenario refintwitherror 'offline verify failed' 'RefintNotUpheld(319)'

# Err(...) token hidden inside otherwise-benign boilerplate (the logging
# pipeline notice) on a nonzero verify: fatal.
make_scenario strayerr 1
cat > "$SCEN/strayerr/verify.txt" <<'EOF'
Logging filter initialized: "kanidm_core::https::trace=info,tonic=warn,h2=warn" Err(OtherError("x"))
00000000-0000-0000-0000-000000000000 INFO     ｉ [info]: Running in db verification mode ...
00000000-0000-0000-0000-000000000000 ERROR    🚨 [error]: Err(RefintNotUpheld(319))
EOF
stub_scenario strayerr
reject_scenario strayerr 'offline verify failed' 'Err(OtherError("x"))'

# Error-like diagnostics on a nonzero verify (a fatal marker and an explicit
# "verification failed" marker at INFO/WARN level): fatal.
make_scenario errormarkers 1
cat > "$SCEN/errormarkers/verify.txt" <<'EOF'
Logging filter initialized: "kanidm_core::https::trace=info,tonic=warn,h2=warn"
00000000-0000-0000-0000-000000000000 INFO     ｉ [info]: Running in db verification mode ...
00000000-0000-0000-0000-000000000000 ERROR    🚨 [error]: Err(RefintNotUpheld(319))
00000000-0000-0000-0000-000000000000 INFO     ｉ [info]: reindex aborted: fatal database state
00000000-0000-0000-0000-000000000000 WARN     🚧 [warn]: Verification failed for 1 entries
EOF
stub_scenario errormarkers
reject_scenario errormarkers 'offline verify failed' 'Verification failed for 1 entries'

# --- cleanup gate: a failing rm is fatal before ownership repair ---

# Clean verify with a failing rm: the explicit checked cleanup refuses to
# proceed to chown. (Run inline: the stub_scenario TMPDIR-empty assertion does
# not apply because the temporary log is intentionally left by the failing rm.)
make_scenario cleanupfailure 0
cat > "$SCEN/cleanupfailure/verify.txt" <<'EOF'
Logging filter initialized: "kanidm_core::https::trace=info,tonic=warn,h2=warn"
00000000-0000-0000-0000-000000000000 INFO     ｉ [info]: Running in db verification mode ...
Verification passed!
EOF
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/rm-fail"
chmod +x "$WORK/rm-fail"
RM_STUB="$WORK/rm-fail"
rm -f "$WORK/chown.log"
KANIDMD="$STUB" render_script "$WORK/stub-cleanupfailure.sh" "$OWNER" "$SYSTL_INACTIVE" "$CHOWN_STUB"
set +e
SCENARIO_DIR="$SCEN/cleanupfailure" "$WORK/stub-cleanupfailure.sh" "$WORK/backup-test.json.gz" >"$WORK/stub-cleanupfailure.sh.log" 2>&1
STUB_RC=$?
set -e
RM_STUB="rm"
if [[ $STUB_RC -eq 0 ]] \
  || ! grep -q 'failed to remove temporary logs' "$WORK/stub-cleanupfailure.sh.log" \
  || grep -q 'Start kanidm.service manually when ready' "$WORK/stub-cleanupfailure.sh.log" \
  || [[ -e "$WORK/chown.log" ]]; then
  echo "kanidm-restore: cleanupfailure must be fatal before ownership repair" >&2
  cat "$WORK/stub-cleanupfailure.sh.log" >&2
  exit 1
fi

# --- runtime restore + verify with the real pinned binary (skips if not built) ---
if [[ ! -x "$KANIDMD" ]]; then
  echo "SKIP kanidm-restore runtime: kanidmd not built at $KANIDMD" >&2
  echo "kanidm-restore-contract: PASS (source contract only)"
  exit 0
fi

cat > "$CONFIG_PATH" <<EOF
domain = "idm.example.com"
origin = "https://idm.example.com:8443"
role = "WriteReplica"
db_path = "$DB_PATH"
db_fs_type = "generic"
adminbindpath = "$WORK/kanidm-admin.sock"
tls_chain = "$WORK/ca.pem"
tls_key = "$WORK/key.pem"
bindaddress = "127.0.0.1:18443"
online_backup = { path = "$WORK/backups", schedule = "5 4 * * *" }
EOF

"$KANIDMD" -c "$CONFIG_PATH" cert-generate >/dev/null 2>&1
mkdir -p "$WORK/backups"

# Upstream constraint: kanidm >= 1.11 stores schema in memory, and its offline
# `database verify` cannot reload schema from a database CREATED by 1.11 itself
# (SchemaViolation(InvalidAttribute("class")) — the reload takes the legacy
# branch because the offline path never loads the domain version). Databases
# created by the 1.10 line keep schema entries in the DB and verify cleanly
# after the 1.11 migration, which is the production upgrade shape. The scratch
# DB is therefore seeded with a 1.10-line binary when one is available in the
# store (same upgrade path la-admin-1 follows); otherwise the runtime section
# skips (fail-closed stub coverage already ran above).
KANIDMD_10="$(ls -d /nix/store/*-kanidm-with-secret-provisioning-1.10.*/bin/kanidmd 2>/dev/null | head -1)"
if [[ -z "$KANIDMD_10" ]]; then
  echo "SKIP kanidm-restore runtime: no 1.10-line kanidmd in store to seed the pre-upgrade scratch DB" >&2
  echo "kanidm-restore-contract: PASS (stub contract only)"
  exit 0
fi
echo "kanidm-restore: seeding scratch DB with 1.10-line binary $KANIDMD_10" >&2

# Initialise a fresh 1.10-level database with a short-lived server run, then
# stop it (the pre-upgrade production shape).
"$KANIDMD_10" -c "$CONFIG_PATH" server >"$WORK/server-init.log" 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 60); do
  if grep -q 'ready to rock' "$WORK/server-init.log" 2>/dev/null; then break; fi
  sleep 1
done
kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true
if [[ ! -f "$DB_PATH" ]]; then
  echo "kanidm-restore: failed to initialise scratch kanidm database" >&2
  tail -5 "$WORK/server-init.log" >&2 || true
  exit 1
fi

# Migrate the DB to the 1.11 domain level with the pinned binary (same as the
# production upgrade), then stop it.
"$KANIDMD" -c "$CONFIG_PATH" server >"$WORK/server-migrate.log" 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 60); do
  if grep -q 'ready to rock' "$WORK/server-migrate.log" 2>/dev/null; then break; fi
  sleep 1
done
kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true

"$KANIDMD" -c "$CONFIG_PATH" database backup "$WORK/backups/backup-test.json.gz" >/dev/null 2>&1
if [[ ! -f "$WORK/backups/backup-test.json.gz" ]]; then
  echo "kanidm-restore: failed to create scratch backup artifact" >&2
  exit 1
fi

# Happy path: restore then offline verify, manual start message, chown invoked.
CHOWN_STUB="$WORK/chown"
printf '#!/usr/bin/env bash\necho "$@" > "%s/chown.log"\n' "$WORK" > "$CHOWN_STUB"
chmod +x "$CHOWN_STUB"
HAPPY="$WORK/kanidm-restore-happy.sh"
render_script "$HAPPY" "$OWNER" "systemctl" "$CHOWN_STUB"
set +e
OUT="$( "$HAPPY" "$WORK/backups/backup-test.json.gz" 2>&1 )"; rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "kanidm-restore: happy path must exit 0" >&2
  echo "$OUT" >&2
  exit 1
fi
restore_line="$(awk '/Running in restore mode/{print NR}' <<<"$OUT" | head -1)"
verify_line="$(awk '/Running in db verification mode/{print NR}' <<<"$OUT" | head -1)"
if [[ -z "$restore_line" || -z "$verify_line" || "$restore_line" -ge "$verify_line" ]]; then
  echo "kanidm-restore: restore must complete before offline verify" >&2
  echo "$OUT" >&2
  exit 1
fi
if ! grep -q 'Verification passed' <<<"$OUT"; then
  echo "kanidm-restore: offline verify must pass" >&2
  echo "$OUT" >&2
  exit 1
fi
if ! grep -q 'Start kanidm.service manually when ready' <<<"$OUT"; then
  echo "kanidm-restore: must state that Kanidm start remains manual" >&2
  echo "$OUT" >&2
  exit 1
fi
if ! grep -q -- "-R $OWNER $WORK" "$WORK/chown.log"; then
  echo "kanidm-restore: ownership repair must run after restore+verify (chown -R $OWNER $WORK)" >&2
  cat "$WORK/chown.log" >&2
  exit 1
fi

# Real-binary CLI contracts for the helper's command shapes: `version` (never
# `--version`) and `database verify`. The helper no longer references db-scan;
# its CLI contract is limited to the two commands the fail-closed gate runs.
set +e
version_out="$("$KANIDMD" version 2>&1)"; version_rc=$?
verify_out="$("$KANIDMD" -c "$CONFIG_PATH" database verify 2>&1)"; verify_rc=$?
set -e
if [[ $version_rc -ne 0 ]] || [[ "$version_out" != "kanidmd 1.11."* ]]; then
  echo "kanidm-restore: 'kanidmd version' must exit 0 and print 'kanidmd 1.11.x'" >&2
  echo "$version_out" >&2
  exit 1
fi
if [[ $verify_rc -ne 0 ]] || ! grep -q 'Verification passed' <<<"$verify_out"; then
  echo "kanidm-restore: 'database verify' must exit 0 with 'Verification passed' on the migrated scratch DB" >&2
  echo "$verify_out" >&2
  exit 1
fi

echo "kanidm-restore-contract: PASS"
