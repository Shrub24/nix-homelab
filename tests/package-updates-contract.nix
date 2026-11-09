# The scheduled updater's decision path: an aborted batch publishes nothing, a
# run that changed nothing leaves the branch and pull request alone, and the
# batch never sees the credential that can push. The publish call itself needs
# the forge, so it is not exercised here.
{
  config,
  lib,
  pkgs,
}:
let
  primaryRepo = {
    owner = "Shrub24";
    name = "nix-homelab";
    branch = "main";
    ref = "refs/heads/main";
    tag = null;
    rev = "0000000000000000000000000000000000000000";
    shortRev = "0000000";
    remoteHttpUrl = "https://github.com/Shrub24/nix-homelab";
    forgeType = "github";
  };
  schedule =
    (config.flake.herculesCI {
      inherit primaryRepo;
      herculesCI = {
        apiBaseUrl = "https://ci.shrublab.xyz";
        ciSystems = null;
      };
    }).onSchedule.package-updates;
  effect = schedule.outputs.effects.update;
in
assert lib.assertMsg effect.__nixbot_effect_checkout "the updater must run in a pushable checkout";
assert lib.assertMsg (
  effect.passthru.lock == "package-updates"
) "the updater needs one named producer lock";
assert lib.assertMsg (
  builtins.length schedule.when.dayOfWeek == 1
) "the updater runs on a weekly schedule";
pkgs.runCommandLocal "package-updates-contract"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.jq
      pkgs.python3
    ];
    effectScript = pkgs.writeText "package-updates-script" (
      builtins.unsafeDiscardStringContext effect.effectScript
    );
  }
  ''
    mkdir -p bin checkout
    cat > bin/nix <<'SH'
    #!${pkgs.runtimeShell}
    set -euo pipefail
    printf 'batch %s\n' "$*" >> "$CALLS"
    report= body=
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --json) report="$2"; shift 2 ;;
        --markdown) body="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    cp "$REPORT_SRC" "$report"
    : > "$body"
    exit "''${BATCH_EXIT:-0}"
    SH
    cat > bin/jj <<'SH'
    #!${pkgs.runtimeShell}
    printf 'jj %s\n' "$*" >> "$CALLS"
    SH
    cat > bin/git <<'SH'
    #!${pkgs.runtimeShell}
    printf 'git %s\n' "$*" >> "$CALLS"
    if [[ -n ''${DIRTY:-} ]]; then echo ' M changed'; fi
    SH
    chmod +x bin/*
    export PATH="$PWD/bin:$PATH" CALLS="$PWD/calls"
    export NIXBOT_EFFECT_CHECKOUT="$PWD/checkout"
    export HERCULES_CI_SECRETS_JSON="$PWD/secrets.json"
    printf '{"token":{"data":{"token":"fixture"}}}' > "$HERCULES_CI_SECRETS_JSON"

    aborted=$PWD/aborted.json
    empty=$PWD/empty.json
    printf '{"outcome":"aborted","packages":[]}' > "$aborted"
    printf '{"outcome":"complete","packages":[]}' > "$empty"

    if BATCH_EXIT=2 REPORT_SRC="$aborted" bash "$effectScript" 2>/dev/null; then
      echo 'the updater published an aborted batch' >&2
      exit 1
    fi

    : > "$CALLS"
    BATCH_EXIT=0 REPORT_SRC="$empty" bash "$effectScript"
    python3 - <<'PY'
    import os
    from pathlib import Path
    calls = Path(os.environ["CALLS"]).read_text().splitlines()
    assert any(c.startswith("batch ") for c in calls), "the batch must run"
    assert not any("push" in c for c in calls), (
        f"an unchanged tree must leave the branch alone: {calls}"
    )
    PY

    : > "$CALLS"
    cat > bin/nix <<'SH'
    #!${pkgs.runtimeShell}
    set -euo pipefail
    if [[ -n "''${HERCULES_CI_SECRETS_JSON:-}" ]]; then
      echo 'the batch inherited the secret file' >&2
      exit 7
    fi
    report=
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --json) report="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    cp "$REPORT_SRC" "$report"
    SH
    chmod +x bin/nix
    if ! REPORT_SRC="$empty" bash "$effectScript"; then
      echo 'the updater batch inherited the secret file' >&2
      exit 1
    fi
    touch "$out"
  ''
