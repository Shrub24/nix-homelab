#!/usr/bin/env bash
set -euo pipefail

# Focused backup-surface contract test (migrate-admin-host-to-la task 6.1a).
# Keeps only the executed-behavior and safety-relevant cases:
#   - the state-restore-stage helper, executed against hostile arguments
#     (relative include path, empty snapshot, leading-dash snapshot, --decode
#     invalid base64, and decoded hostile values) through a local render that
#     exits before touching secrets or restic
#   - the static safety shape of the helper's real restic invocation
#     (end-of-options, root-only staging dir, stdout discipline) that cannot be
#     exercised without restic
#   - the `just backups restore-stage` recipe transport through a stub ssh:
#     hostile host/user/local-command values are rejected or base64-transported
#     with no local command execution
# Attribute-selected evals keep this fast; whole-attrset forcing of
# services.postgresqlBackup is deliberately avoided because nixpkgs' removed
# `period` option throws when its hidden value is forced.

LA='path:.#nixosConfigurations.la-admin-1.config'

# ── Restore-staging helper ────────────────────────────────────────────────
# The operator helper restores exactly one absolute include path into a fresh
# root-only staging dir, prints ONLY the destination path on stdout, reuses
# the module's exact repository/credentials/backend options, and accepts no
# arbitrary restic flags. No destination argument exists, so live paths cannot
# be chosen.

HELPER_TEXT="$(nix eval --no-write-lock-file --raw "$LA.services.state-backups.restoreStagePackage.text")"
# Static contract: diagnostics go to stderr, exactly one stdout echo of the
# destination path; snapshot validated against empty/leading-dash; include path
# absolute and without ".."; parent repaired root-owned 0700; restic invoked
# with end-of-options before the snapshot and its own stdout redirected.
case "$HELPER_TEXT" in
  *"usage: state-restore-stage [--decode <snapshot-b64> <include-path-b64>] <snapshot> <absolute-include-path>"*) ;;
  *) echo "backup-surface: state-restore-stage must expose --decode plus snapshot + include path" >&2; exit 1 ;;
esac
case "$HELPER_TEXT" in
  *"snapshot must not be empty"*) ;;
  *) echo "backup-surface: state-restore-stage must reject empty snapshots" >&2; exit 1 ;;
esac
case "$HELPER_TEXT" in
  *"must not start with '-'"*) ;;
  *) echo "backup-surface: state-restore-stage must reject leading-dash snapshots" >&2; exit 1 ;;
esac
case "$HELPER_TEXT" in
  *"must be absolute"*) ;;
  *) echo "backup-surface: state-restore-stage must reject relative include paths" >&2; exit 1 ;;
esac
case "$HELPER_TEXT" in
  *"install -d -m 0700 -o root -g root /var/tmp/state-restore"*) ;;
  *) echo "backup-surface: state-restore-stage must repair the staging parent root-owned 0700" >&2; exit 1 ;;
esac
case "$HELPER_TEXT" in
  *"restore --target \"\$dest\" --include \"\$include_path\" -- \"\$snapshot\""*) ;;
  *) echo "backup-surface: state-restore-stage must pass end-of-options before the snapshot" >&2; exit 1 ;;
esac
case "$HELPER_TEXT" in
  *" 1>&2"*"echo \"\$dest\""*) ;;
  *) echo "backup-surface: state-restore-stage must redirect restic stdout to stderr and print only the destination path" >&2; exit 1 ;;
esac

# Execute the helper's validation paths (LA text: x86_64 store paths run on
# this machine). All of these must exit before touching secrets or restic.
HELPER_FILE="$(mktemp)"
printf '%s\n' "$HELPER_TEXT" > "$HELPER_FILE"
chmod +x "$HELPER_FILE"
ERR="$(mktemp)"

# Relative include path -> exit 2, empty stdout, diagnostic on stderr.
set +e
OUT="$(bash "$HELPER_FILE" latest 'relative/path' 2>"$ERR")"
RC=$?
set -e
[ "$RC" -eq 2 ] || { echo "backup-surface: relative include path must exit 2, got $RC" >&2; exit 1; }
[ -z "$OUT" ] || { echo "backup-surface: validation failures must print nothing to stdout" >&2; exit 1; }
grep -q "must be absolute" "$ERR" || { echo "backup-surface: relative include path must be diagnosed" >&2; exit 1; }

# Empty snapshot -> exit 2, empty stdout.
set +e
OUT="$(bash "$HELPER_FILE" '' /srv/data/x 2>"$ERR")"
RC=$?
set -e
[ "$RC" -eq 2 ] || { echo "backup-surface: empty snapshot must exit 2, got $RC" >&2; exit 1; }
[ -z "$OUT" ] || { echo "backup-surface: empty-snapshot rejection must print nothing to stdout" >&2; exit 1; }

# Leading-dash snapshot -> exit 2, empty stdout (no restic flag injection).
set +e
OUT="$(bash "$HELPER_FILE" -evil /srv/data/x 2>"$ERR")"
RC=$?
set -e
[ "$RC" -eq 2 ] || { echo "backup-surface: leading-dash snapshot must exit 2, got $RC" >&2; exit 1; }
[ -z "$OUT" ] || { echo "backup-surface: leading-dash rejection must print nothing to stdout" >&2; exit 1; }

# --decode mode: invalid base64 charset -> exit 2.
set +e
OUT="$(bash "$HELPER_FILE" --decode '!!!' '!!!' 2>"$ERR")"
RC=$?
set -e
[ "$RC" -eq 2 ] || { echo "backup-surface: invalid base64 must exit 2, got $RC" >&2; exit 1; }
[ -z "$OUT" ] || { echo "backup-surface: invalid-base64 rejection must print nothing to stdout" >&2; exit 1; }

# --decode mode: valid base64 decodes then applies the same validation
# (a leading-dash snapshot encoded as base64 is rejected after decoding).
set +e
OUT="$(bash "$HELPER_FILE" --decode "$(printf '%s' -dash | base64 -w0)" "$(printf '%s' /srv/data/x | base64 -w0)" 2>"$ERR")"
RC=$?
set -e
[ "$RC" -eq 2 ] || { echo "backup-surface: decoded leading-dash snapshot must exit 2, got $RC" >&2; exit 1; }
[ -z "$OUT" ] || { echo "backup-surface: decoded rejection must print nothing to stdout" >&2; exit 1; }

# --decode mode: valid values decode and reach the environment check without
# touching secrets (no rendered env file on this machine -> exit 1).
set +e
OUT="$(bash "$HELPER_FILE" --decode "$(printf '%s' abc123 | base64 -w0)" "$(printf '%s' /srv/data/x | base64 -w0)" 2>"$ERR")"
RC=$?
set -e
[ "$RC" -eq 1 ] || { echo "backup-surface: decoded valid args must reach env-file check (exit 1), got $RC" >&2; exit 1; }
[ -z "$OUT" ] || { echo "backup-surface: env-check failure must print nothing to stdout" >&2; exit 1; }
grep -q "missing restic environment file" "$ERR" || { echo "backup-surface: decoded valid args must reach the env-file check" >&2; exit 1; }
rm -f "$HELPER_FILE" "$ERR"

# ── Just recipe: hostile-argument transport safety ────────────────────────
# Execute the recipe with hostile values through a stub ssh: prove no local
# command executes (markers), the remote command contains only base64-alphabet
# characters in a static shape, and the base64 decodes back to the exact
# hostile values. Hostile host/user must be rejected before ssh is called.
FAKEBIN="$(mktemp -d)"
cat > "$FAKEBIN/ssh" <<'EOF'
#!/usr/bin/env bash
printf 'argc=%d\n' "$#"
i=0
for a in "$@"; do
  i=$((i+1))
  printf 'ARG%d=%s\n' "$i" "$a"
done
exit 0
EOF
chmod +x "$FAKEBIN/ssh"
trap 'rm -rf "$FAKEBIN"' EXIT

MARKER1="$(mktemp -u /tmp/opencode/backup-surface-pwn1.XXXXXX)"
MARKER2="$(mktemp -u /tmp/opencode/backup-surface-pwn2.XXXXXX)"
rm -f "$MARKER1" "$MARKER2"

HOSTILE_SNAP='-$(touch '"$MARKER1"') `touch '"$MARKER2"'` "quoted" spaced'
HOSTILE_INC='$(touch '"$MARKER2"') `touch '"$MARKER1"'` "quoted" spaced'

set +e
OUTPUT="$(PATH="$FAKEBIN:$PATH" just backups restore-stage valid-host -- "$HOSTILE_SNAP" "$HOSTILE_INC" 2>&1)"
RC=$?
set -e
[ "$RC" -eq 0 ] || { echo "backup-surface: just restore-stage must succeed with hostile args (transport only), rc=$RC" >&2; printf '%s\n' "$OUTPUT" >&2; exit 1; }
[ ! -e "$MARKER1" ] && [ ! -e "$MARKER2" ] || { echo "backup-surface: hostile args executed locally" >&2; exit 1; }

OUTPUT="$OUTPUT" python3 - "$HOSTILE_SNAP" "$HOSTILE_INC" <<'PY'
import base64, os, re, sys
lines = os.environ["OUTPUT"].splitlines()
if not lines or lines[0] != "argc=2":
    raise SystemExit("backup-surface: stub ssh must receive exactly 2 args, got: %r" % lines)
args = {}
for l in lines[1:]:
    k, _, v = l.partition("=")
    args[k] = v
if args.get("ARG1") != "dev@valid-host":
    raise SystemExit("backup-surface: SSH destination must be user@host, got: %r" % args.get("ARG1"))
m = re.fullmatch(r"sudo state-restore-stage --decode '([A-Za-z0-9+/=]+)' '([A-Za-z0-9+/=]+)'", args.get("ARG2", ""))
if not m:
    raise SystemExit("backup-surface: remote command must be static with only base64-alphabet args, got: %r" % args.get("ARG2"))
snap = base64.b64decode(m.group(1)).decode()
inc = base64.b64decode(m.group(2)).decode()
if snap != sys.argv[1]:
    raise SystemExit("backup-surface: snapshot base64 round-trip mismatch: %r != %r" % (snap, sys.argv[1]))
if inc != sys.argv[2]:
    raise SystemExit("backup-surface: include-path base64 round-trip mismatch: %r != %r" % (inc, sys.argv[2]))
PY

# Hostile SSH destination must be rejected locally before any ssh call.
set +e
OUTPUT2="$(PATH="$FAKEBIN:$PATH" just backups restore-stage '$(touch '"$MARKER1"')' "$HOSTILE_SNAP" "$HOSTILE_INC" 2>&1)"
RC2=$?
set -e
[ "$RC2" -ne 0 ] || { echo "backup-surface: hostile host must fail the recipe" >&2; exit 1; }
[ ! -e "$MARKER1" ] || { echo "backup-surface: hostile host executed locally" >&2; exit 1; }
case "$OUTPUT2" in
  *ARG*) echo "backup-surface: ssh must not be called for a hostile host" >&2; printf '%s\n' "$OUTPUT2" >&2; exit 1 ;;
esac

# The just recipe source keeps the static transport shape and no-cd.
BACKUPS_JUST=".just/backups.just"
if ! grep -q '^restore-stage ' "$BACKUPS_JUST" \
  || ! grep -q -- '--decode' "$BACKUPS_JUST" \
  || ! grep -q 'base64 -w0' "$BACKUPS_JUST" \
  || ! grep -q 'set no-cd' "$BACKUPS_JUST" \
  || ! grep -q 'SNAP64' "$BACKUPS_JUST" \
  || ! grep -q 'INC64' "$BACKUPS_JUST"; then
  echo "backup-surface: just restore-stage recipe must base64-transport args in a static remote command" >&2
  exit 1
fi

echo "check-backup-surface-contract: PASS"
