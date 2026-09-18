#!/usr/bin/env bash
set -euo pipefail
# Index-integrity guard for the Git-tree flake reference form
# (restrict-provenance-source-copy, design PSC-1/PSC-2).
#
# Every local reference to this flake uses `.#`, which resolves the repository's
# Git tree. That tree is built from the Git *index*: a file that jj tracks but
# the index does not is silently absent from evaluation, from `.#` builds, and
# from the `/etc/nixos-source` copy they publish. Stage 8 hit exactly that after
# an external `git reset` removed 19 tracked files from the index, and the only
# symptom was an unrelated-looking evaluation error, so the condition is checked
# here instead of being rediscovered.
#
# The check never mutates this repository: the fire proof runs in a scratch
# fixture under $TMPDIR.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "check-flake-source-tracking: $*" >&2
  exit 1
}

git_index() { # $1 repo dir -> sorted index paths
  ( cd "$1" && git ls-files | LC_ALL=C sort -u )
}

jj_tracked() { # $1 repo dir -> sorted working-copy file paths
  ( cd "$1" && jj file list -r @ 2>/dev/null | LC_ALL=C sort -u )
}

divergence() { # $1 repo dir -> jj-tracked paths missing from the Git index
  # LC_ALL=C on both the sorts and here: a locale-sorted list compared by a
  # C-locale comm (or the reverse) fails with "input is not in sorted order".
  LC_ALL=C comm -23 <(jj_tracked "$1") <(git_index "$1")
}

# jj is the tracking authority in this repository; without it the comparison
# cannot be made, and guessing would be worse than skipping loudly. The skip is
# only honest when there is nothing to compare: if this is a jj working copy and
# jj is missing or failing, the check cannot vouch for the index and must fail
# closed rather than report a clean tree it never inspected.
if ! command -v jj >/dev/null 2>&1; then
  if [ -d "$ROOT/.jj" ]; then
    fail "jj is not available but $ROOT is a jj working copy: cannot verify that the Git index matches tracked files. Install jj and re-run (this check must not pass blind)."
  fi
  echo "check-flake-source-tracking: SKIP (no jj working copy)"
  exit 0
fi
if ! ( cd "$ROOT" && git rev-parse --git-dir >/dev/null 2>&1 ); then
  echo "check-flake-source-tracking: SKIP (not a git-backed working copy)"
  exit 0
fi
if ! ( cd "$ROOT" && jj file list -r @ >/dev/null 2>&1 ); then
  fail "jj file list -r @ failed in this jj working copy: the index comparison cannot run. Fix the jj error and re-run (this check must not pass blind)."
fi

# An empty index would make every tracked file "divergent" or, with a naive
# inversion, let the check pass without comparing anything. Neither is a clean
# state: fail explicitly instead of reporting a misleading result.
index_count="$(git_index "$ROOT" | wc -l)"
[ "$index_count" -gt 0 ] ||
  fail "the Git index is empty: nothing to compare. Repair with: git add -A"

missing="$(divergence "$ROOT")"
if [ -n "$missing" ]; then
  {
    echo "check-flake-source-tracking: tracked files are missing from the Git index."
    echo "The Git-tree flake form (.#) copies tracked content only, so a partial"
    echo "index silently evaluates a partial tree and publishes a partial"
    echo "/etc/nixos-source. Missing paths:"
    printf '  %s\n' $missing
    echo "Repair: git add -A"
    echo "Do not use git reset / git checkout / git stash in this colocated"
    echo "repository; jj operations are the interface."
  } >&2
  exit 1
fi

# Fire proof: a scratch jj+git fixture whose index loses a tracked file must be
# reported by the same predicate. This proves the check is not vacuous on a
# tree that happens to be complete.
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/flake-source-tracking.XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT
fixture_ok=1
if ( cd "$FIXTURE" && git init -q . >/dev/null 2>&1 &&
  JJ_USER=fixture JJ_EMAIL=fixture@example.invalid jj git init --colocate . >/dev/null 2>&1 ); then
  printf 'a\n' >"$FIXTURE/kept.nix"
  printf 'b\n' >"$FIXTURE/dropped.nix"
  ( cd "$FIXTURE" && JJ_USER=fixture JJ_EMAIL=fixture@example.invalid jj status >/dev/null 2>&1 ) || fixture_ok=0
else
  fixture_ok=0
fi
if [ "$fixture_ok" -eq 1 ]; then
  ( cd "$FIXTURE" && git rm -q --cached dropped.nix ) ||
    fail "fixture preparation failed: cannot drop an index entry in the scratch repository"
  fixture_missing="$(divergence "$FIXTURE")"
  [ "$fixture_missing" = "dropped.nix" ] ||
    fail "predicate is vacuous: dropping an index entry in the scratch fixture reported '$fixture_missing' instead of 'dropped.nix'"
else
  echo "check-flake-source-tracking: note: scratch jj fixture unavailable; predicate self-test skipped"
fi

echo "check-flake-source-tracking: PASS"
