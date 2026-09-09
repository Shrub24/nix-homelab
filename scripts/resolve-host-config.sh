#!/usr/bin/env bash
# usage: source scripts/resolve-host-config.sh <host>
# sets: TARGET_HOST, BOOTSTRAP_USER, FLAKE, HARDWARE_CONFIG_GENERATOR,
#       HARDWARE_CONFIG_PATH
#
# Every value resolves from the typed flake output path:.#bootstrap.nodes.<host>
# (registry projection, design DS-6); nothing here parses Nix source text.
set -euo pipefail

HOST="$1"

if ! nix eval --no-write-lock-file "path:.#bootstrap.nodes.${HOST}" >/dev/null 2>&1; then
  echo "Error: no bootstrap metadata found for host '${HOST}' (flake.bootstrap.nodes.${HOST})" >&2
  exit 1
fi

bootstrap_attr() {
  local attr="$1"
  nix eval --no-write-lock-file --raw \
    --apply "v: v.${attr} or \"\"" \
    "path:.#bootstrap.nodes.${HOST}"
}

TARGET_HOST="$(bootstrap_attr hostName)"
BOOTSTRAP_USER="$(bootstrap_attr bootstrapUser)"
FLAKE="$(bootstrap_attr flake)"
# Optional: exported empty when the host declares no hardware-config
# generation; deploy.sh keeps enforcing the both-or-none rule.
HARDWARE_CONFIG_GENERATOR="$(bootstrap_attr hardwareConfigGenerator)"
HARDWARE_CONFIG_PATH="$(bootstrap_attr hardwareConfigPath)"

export TARGET_HOST BOOTSTRAP_USER FLAKE HARDWARE_CONFIG_GENERATOR HARDWARE_CONFIG_PATH
