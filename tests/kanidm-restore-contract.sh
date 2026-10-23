#!/usr/bin/env bash
set -euo pipefail
# Execute the evaluated Kanidm restore helper with temporary paths and stubs
# at external command boundaries, and assert the evaluated unit wiring: the
# helper receives the operator's artifact path through %I and the unit is never
# activated at boot. No remote operations or real database.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

EVALUATED=$(nix eval --no-write-lock-file --raw --apply 'c: builtins.toJSON {
  execStart = c.systemd.services."kanidm-restore@".serviceConfig.ExecStart;
  helperDrv = c.system.build.kanidm-restore.drvPath;
  serviceType = c.systemd.services."kanidm-restore@".serviceConfig.Type;
  wantedBy = c.systemd.services."kanidm-restore@".wantedBy;
  restoreUnits = builtins.filter (n: builtins.match ".*kanidm-restore.*" n != null) (builtins.attrNames c.systemd.services);
  restoreTimers = builtins.filter (n: builtins.match ".*kanidm-restore.*" n != null) (builtins.attrNames c.systemd.timers);
  dbPath = c.services.kanidm.server.settings.db_path;
}' path:.#nixosConfigurations.la-admin-1.config) || {
  echo "kanidm-restore: evaluated unit wiring does not evaluate" >&2
  exit 1
}
readarray -t HELPER_INFO < <(python3 -c 'import json,sys; x=json.load(sys.stdin); print(x["execStart"]); print(x["dbPath"]); print(x["helperDrv"])' <<< "$EVALUATED")
HELPER=${HELPER_INFO[0]%% *}
PRODUCTION_DB_PATH=${HELPER_INFO[1]}
HELPER_DRV=${HELPER_INFO[2]}
case "$HELPER" in /nix/store/*-kanidm-restore) ;; *) echo "unexpected evaluated helper path: $HELPER" >&2; exit 1 ;; esac

# The helper is a build output: realise it before reading its content, or a cold
# store (CI, a fresh machine) finds the evaluated path missing. The `^*` suffix
# is load-bearing: `nix build --no-link <drv>` exits 0 without building anything
# when the output is absent, so the bare path silently leaves the store cold.
nix build --no-link --impure "$HELPER_DRV^*" || { echo "kanidm-restore: evaluated helper derivation failed to build" >&2; exit 1; }

# Evaluated wiring contract: the executed cases below start the helper
# directly, so only these assertions cover the operator's invocation path.
python3 - "$EVALUATED" <<'PYEOF' || { echo "kanidm-restore: evaluated unit wiring contract violated" >&2; exit 1; }
import json, sys

x = json.loads(sys.argv[1])
errs = []
if not x["execStart"].endswith(" %I"):
    errs.append(f"the unit must forward the operator's artifact path as %I: {x['execStart']!r}")
if x["serviceType"] != "oneshot":
    errs.append(f"the restore unit must stay a one-shot: {x['serviceType']!r}")
if x["wantedBy"]:
    errs.append(f"the restore unit must not be pulled in at boot: wantedBy={x['wantedBy']!r}")
if x["restoreUnits"] != ["kanidm-restore@"]:
    errs.append(f"only the operator-invoked template may exist: {x['restoreUnits']!r}")
if x["restoreTimers"]:
    errs.append(f"the restore must never be timer-activated: {x['restoreTimers']!r}")
if errs:
    print("\n".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF
CONFIG_PATH="$WORK/server.toml"
DB_PATH="$WORK/kanidm.db"

render_script() {
  # $1 output; optional $2 systemctl stub, $3 kanidmd stub, $4 chown stub,
  # $5 rm stub. Refuse incomplete substitution rather than risk real paths.
  local output="$1" systemctl_path="${2:-$(command -v systemctl)}" kanidmd_path="${3:-$(command -v true)}"
  local chown_path="${4:-$(command -v chown)}" rm_path="${5:-$(command -v rm)}"
  python3 - "$HELPER" "$output" "$CONFIG_PATH" "$PRODUCTION_DB_PATH" "$DB_PATH" \
    "$systemctl_path" "$kanidmd_path" "$chown_path" "$rm_path" <<'PYEOF'
import pathlib, re, shutil, sys

src = pathlib.Path(sys.argv[1]).read_text()
for old, new in (("/etc/kanidm/server.toml", sys.argv[3]), (sys.argv[4], sys.argv[5])):
    if old not in src:
        raise SystemExit(f"evaluated helper substitution anchor missing: {old}")
    src = src.replace(old, new)
for command, replacement in (
    ("systemctl", sys.argv[6]), ("kanidmd", sys.argv[7]),
    ("chown", sys.argv[8]), ("rm", sys.argv[9]),
    ("cat", None), ("dirname", None), ("mkdir", None),
    ("mktemp", None), ("grep", None),
):
    replacement = replacement or shutil.which(command)
    if not replacement:
        raise SystemExit(f"required command unavailable for helper substitution: {command}")
    src, count = re.subn(rf"/nix/store/[a-z0-9]{{32}}-[^/]+/bin/{command}", replacement, src)
    if count == 0:
        raise SystemExit(f"evaluated helper command anchor missing: {command}")
for unsafe in ("/etc/kanidm/server.toml", sys.argv[4]):
    if unsafe in src:
        raise SystemExit(f"unsafe production path remains after substitution: {unsafe}")
pathlib.Path(sys.argv[2]).write_text(src)
PYEOF
  chmod +x "$output"
}

RENDERED="$WORK/kanidm-restore.sh"
render_script "$RENDERED"
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
render_script "$REFUSAL" "$SYSTL_STUB"
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
# Stub of kanidmd for restore-helper contract scenarios. The
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
  render_script "$out" "$SYSTL_INACTIVE" "$STUB" "$CHOWN_STUB"
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
if [[ $STUB_RC -ne 0 ]] || ! grep -q 'Verification passed' "$WORK/stub-clean.sh.log" || ! grep -q 'Start kanidm.service manually when ready' "$WORK/stub-clean.sh.log" || ! grep -q -- "-R kanidm:kanidm $(dirname "$DB_PATH")" "$WORK/chown.log"; then
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
rm -f "$WORK/chown.log"
render_script "$WORK/stub-cleanupfailure.sh" "$SYSTL_INACTIVE" "$STUB" "$CHOWN_STUB" "$WORK/rm-fail"
set +e
SCENARIO_DIR="$SCEN/cleanupfailure" "$WORK/stub-cleanupfailure.sh" "$WORK/backup-test.json.gz" >"$WORK/stub-cleanupfailure.sh.log" 2>&1
STUB_RC=$?
set -e
if [[ $STUB_RC -eq 0 ]] \
  || ! grep -q 'failed to remove temporary logs' "$WORK/stub-cleanupfailure.sh.log" \
  || grep -q 'Start kanidm.service manually when ready' "$WORK/stub-cleanupfailure.sh.log" \
  || [[ -e "$WORK/chown.log" ]]; then
  echo "kanidm-restore: cleanupfailure must be fatal before ownership repair" >&2
  cat "$WORK/stub-cleanupfailure.sh.log" >&2
  exit 1
fi

echo "kanidm-restore-contract: PASS"
