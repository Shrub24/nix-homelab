#!/usr/bin/env bash
set -euo pipefail

# Focused backup-surface contract test (migrate-admin-host-to-la task 6.1a).
# Keeps only the executed-behavior and safety-relevant cases:
#   - the state-restore-stage helper, executed against hostile arguments
#     (relative include path, empty snapshot, leading-dash snapshot, --decode
#     invalid base64, and decoded hostile values) through a local render that
#     exits before touching secrets or restic
#   - the helper's successful staging path, executed with scratch paths and
#     stubs at the filesystem/restic boundary: the staging parent is repaired
#     root-owned 0700, restic runs with end-of-options before the snapshot, its
#     own stdout is redirected to stderr, and stdout carries only the created
#     0700 destination directory
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
# Execute the helper's validation paths. All of these must exit before
# touching secrets or restic.
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

# ── Executed success path: staging mode, redirection, stdout discipline ───
# The evaluated helper text is copied with explicit, fail-loud substitutions:
# scratch staging parent and env file, and stubs for the filesystem/restic
# boundaries. Nothing here touches the production staging path, /run/secrets,
# or a restic repository.
RESTIC_ENV_PRODUCTION="$(nix eval --no-write-lock-file --raw "$LA.sops.templates.\"state-backups.env\".path")"
STAGING_ROOT="$(mktemp -d)"
STAGING_PARENT="$STAGING_ROOT/state-restore"
SUCCESS_RUN="$(mktemp -d)"
STUBDIR="$SUCCESS_RUN/stub"
mkdir -p "$STUBDIR" "$SUCCESS_RUN/argv"

cat > "$STUBDIR/install" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_LOG/install.argv"
mkdir -p -m 0700 -- "${@: -1}"
EOF
cat > "$STUBDIR/restic" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_LOG/restic.argv"
echo "restic: restore progress on stdout"
EOF
chmod +x "$STUBDIR/install" "$STUBDIR/restic"
printf 'SCRATCH_ENV=1\n' > "$SUCCESS_RUN/state-backups.env"

SUCCESS_HELPER="$SUCCESS_RUN/state-restore-stage"
STUBDIR="$STUBDIR" STUB_LOG="$SUCCESS_RUN/argv" STAGING_PARENT="$STAGING_PARENT" \
  RESTIC_ENV_PRODUCTION="$RESTIC_ENV_PRODUCTION" SCRATCH_ENV_FILE="$SUCCESS_RUN/state-backups.env" \
  python3 - "$HELPER_TEXT" "$SUCCESS_HELPER" <<'PYEOF'
import os, pathlib, re, shutil, sys

src = sys.argv[1]
for old, new in (
    ("/var/tmp/state-restore", os.environ["STAGING_PARENT"]),
    (os.environ["RESTIC_ENV_PRODUCTION"], os.environ["SCRATCH_ENV_FILE"]),
):
    if old not in src:
        raise SystemExit(f"state-restore-stage substitution anchor missing: {old}")
    src = src.replace(old, new)
for command, replacement in (
    ("install", os.path.join(os.environ["STUBDIR"], "install")),
    ("restic", os.path.join(os.environ["STUBDIR"], "restic")),
    ("rm", shutil.which("rm")),
    ("mktemp", shutil.which("mktemp")),
    ("base64", shutil.which("base64")),
):
    if not replacement:
        raise SystemExit(f"required command unavailable for helper substitution: {command}")
    src, count = re.subn(rf"/nix/store/[a-z0-9]{{32}}-[^/\s]+/bin/{command}", replacement, src)
    if count == 0:
        raise SystemExit(f"state-restore-stage command anchor missing: {command}")
for unsafe in ("/var/tmp/state-restore", os.environ["RESTIC_ENV_PRODUCTION"]):
    if unsafe in src:
        raise SystemExit(f"unsafe production path remains after substitution: {unsafe}")
pathlib.Path(sys.argv[2]).write_text(src)
PYEOF
chmod +x "$SUCCESS_HELPER"
bash -n "$SUCCESS_HELPER"

set +e
SUCCESS_OUT="$(STUB_LOG="$SUCCESS_RUN/argv" "$SUCCESS_HELPER" latest /srv/data/pg 2>"$SUCCESS_RUN/stderr")"
SUCCESS_RC=$?
set -e
if [ "$SUCCESS_RC" -ne 0 ]; then
  echo "backup-surface: successful restore staging must exit 0, got $SUCCESS_RC" >&2
  cat "$SUCCESS_RUN/stderr" >&2 || true
  exit 1
fi
case "$SUCCESS_OUT" in
  *$'\n'*) echo "backup-surface: staging must print exactly one line on stdout" >&2; exit 1 ;;
esac
case "$SUCCESS_OUT" in
  "$STAGING_PARENT"/restore.*) ;;
  *) echo "backup-surface: staging must create its destination under the staging parent, got '$SUCCESS_OUT'" >&2; exit 1 ;;
esac
[ -d "$SUCCESS_OUT" ] || { echo "backup-surface: staging must print an existing destination directory" >&2; exit 1; }
[ "$(stat -c %a "$SUCCESS_OUT")" = "700" ] || { echo "backup-surface: the staging destination must be 0700" >&2; exit 1; }
grep -qF 'restic: restore progress on stdout' "$SUCCESS_RUN/stderr" || { echo "backup-surface: restic's own stdout must be redirected to stderr" >&2; exit 1; }

python3 - "$SUCCESS_RUN" "$SUCCESS_OUT" "$STAGING_PARENT" <<'PYEOF' || { echo "backup-surface: executed staging invocation shape violated" >&2; exit 1; }
import os, sys

run, dest, staging = sys.argv[1], sys.argv[2], sys.argv[3]
install = open(os.path.join(run, "argv", "install.argv")).read().split()
restic = open(os.path.join(run, "argv", "restic.argv")).read().split()
errs = []
if install != ["-d", "-m", "0700", "-o", "root", "-g", "root", staging]:
    errs.append(f"staging parent not repaired root-owned 0700: {install!r}")
# The helper's own -o config options may precede the subcommand (they come from
# the module's extraOptions), but nothing else may: the destination is the one
# the helper created and end-of-options keeps the snapshot from being parsed as
# a flag.
expected = ["restore", "--target", dest, "--include", "/srv/data/pg", "--", "latest"]
prefix = restic[: -len(expected)]
if restic[-len(expected) :] != expected:
    errs.append(f"restic invocation shape changed: {restic!r}")
else:
    option_pairs = len(prefix) % 2 == 0 and all(
        prefix[i] == "-o" for i in range(0, len(prefix), 2)
    )
    if not option_pairs:
        errs.append(f"only -o config options may precede the restore subcommand: {restic!r}")
if errs:
    print("\n".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF
rm -rf "$SUCCESS_RUN" "$STAGING_ROOT"

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

echo "check-backup-surface-contract: PASS"
