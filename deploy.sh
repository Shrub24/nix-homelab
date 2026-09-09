#!/usr/bin/env bash
set -euo pipefail

# Values resolve from CLI flags first, then from the environment exported by
# scripts/resolve-host-config.sh (typed flake.bootstrap.nodes projection,
# design DS-6). deploy.sh consumes exported registry values only; it never
# parses host metadata source itself.
TARGET_HOST="${TARGET_HOST:-}"
BOOTSTRAP_USER="${BOOTSTRAP_USER:-}"
FLAKE_TARGET="${FLAKE:-}"
EXTRA_FILES="${EXTRA_FILES:-}"
HARDWARE_CONFIG_GENERATOR="${HARDWARE_CONFIG_GENERATOR:-}"
HARDWARE_CONFIG_PATH="${HARDWARE_CONFIG_PATH:-}"
SKIP_HARDWARE_CONFIG="${SKIP_HARDWARE_CONFIG:-false}"

usage() {
	cat <<EOF
Usage: $0 [--target <host-or-ip>] [--bootstrap-user <user>] [--flake <flake-ref>] [--extra-files <path>] [--hardware-config-generator <name>] [--hardware-config-path <path>] [--skip-hardware-config]

Target, bootstrap user, and flake ref are required; deploy.sh never assumes a
default host. The canonical caller is the just bootstrap recipe (just
bootstrap <host> <addr>), which sources scripts/resolve-host-config.sh to
resolve the host's flake.bootstrap.nodes metadata from the typed registry and
passes the values here as flags or exports (TARGET_HOST, BOOTSTRAP_USER,
FLAKE, HARDWARE_CONFIG_GENERATOR, HARDWARE_CONFIG_PATH).

The temporary installer image's SSH host key is diagnostic only: never derive
a persistent SOPS age recipient from it. Enroll the persistent recipient only
after first boot from the console-verified persistent host key (two-step
secrets bootstrap; see docs/runbooks/host-initialization.md).
EOF
}

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--target)
		if [[ $# -lt 2 ]]; then
			echo "Error: --target requires a value"
			exit 1
		fi
		TARGET_HOST="$2"
		shift 2
		;;
	--bootstrap-user)
		if [[ $# -lt 2 ]]; then
			echo "Error: --bootstrap-user requires a value"
			exit 1
		fi
		BOOTSTRAP_USER="$2"
		shift 2
		;;
	--flake)
		if [[ $# -lt 2 ]]; then
			echo "Error: --flake requires a value"
			exit 1
		fi
		FLAKE_TARGET="$2"
		shift 2
		;;
	--extra-files)
		if [[ $# -lt 2 ]]; then
			echo "Error: --extra-files requires a value"
			exit 1
		fi
		EXTRA_FILES="$2"
		shift 2
		;;
	--hardware-config-generator)
		if [[ $# -lt 2 ]]; then
			echo "Error: --hardware-config-generator requires a value"
			exit 1
		fi
		HARDWARE_CONFIG_GENERATOR="$2"
		shift 2
		;;
	--hardware-config-path)
		if [[ $# -lt 2 ]]; then
			echo "Error: --hardware-config-path requires a value"
			exit 1
		fi
		HARDWARE_CONFIG_PATH="$2"
		shift 2
		;;
	--skip-hardware-config)
		SKIP_HARDWARE_CONFIG="true"
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "Error: unknown argument: $1"
		usage
		exit 1
		;;
	esac
done

normalize_prefixed_value() {
	local key="$1"
	local value="$2"
	if [[ "$value" == "${key}="* ]]; then
		printf '%s' "${value#${key}=}"
	else
		printf '%s' "$value"
	fi
}

TARGET_HOST="$(normalize_prefixed_value target "$TARGET_HOST")"
BOOTSTRAP_USER="$(normalize_prefixed_value user "$BOOTSTRAP_USER")"
FLAKE_TARGET="$(normalize_prefixed_value flake "$FLAKE_TARGET")"
EXTRA_FILES="$(normalize_prefixed_value extra_files "$EXTRA_FILES")"
HARDWARE_CONFIG_GENERATOR="$(normalize_prefixed_value hardware_config_generator "$HARDWARE_CONFIG_GENERATOR")"
HARDWARE_CONFIG_PATH="$(normalize_prefixed_value hardware_config_path "$HARDWARE_CONFIG_PATH")"

if [[ -z "$TARGET_HOST" ]]; then
	echo "Error: target host unresolved; pass --target or export TARGET_HOST (source scripts/resolve-host-config.sh <host>)" >&2
	exit 1
fi

if [[ -z "$BOOTSTRAP_USER" ]]; then
	echo "Error: bootstrap user unresolved; pass --bootstrap-user or export BOOTSTRAP_USER (source scripts/resolve-host-config.sh <host>)" >&2
	exit 1
fi

if [[ -z "$FLAKE_TARGET" ]]; then
	echo "Error: flake ref unresolved; pass --flake or export FLAKE (source scripts/resolve-host-config.sh <host>)" >&2
	exit 1
fi

# Hardware-config generation is opt-in: the resolver exports both values only
# when the host record declares them; there is no shared fallback path.
if [[ "$SKIP_HARDWARE_CONFIG" != "true" ]] && { [[ -n "$HARDWARE_CONFIG_GENERATOR" ]] || [[ -n "$HARDWARE_CONFIG_PATH" ]]; }; then
	if [[ -z "$HARDWARE_CONFIG_GENERATOR" ]] || [[ -z "$HARDWARE_CONFIG_PATH" ]]; then
		echo "Error: the host's registry bootstrap metadata must declare both hardwareConfigGenerator and hardwareConfigPath together (or pass --skip-hardware-config)" >&2
		exit 1
	fi
fi

CMD=(
	nix run github:nix-community/nixos-anywhere --
	--flake "$FLAKE_TARGET"
	--build-on remote
	--target-host "${BOOTSTRAP_USER}@${TARGET_HOST}"
)

if [[ -n "$EXTRA_FILES" ]]; then
	CMD+=(--extra-files "$EXTRA_FILES")
fi

if [[ "$SKIP_HARDWARE_CONFIG" != "true" ]] && [[ -n "$HARDWARE_CONFIG_GENERATOR" ]] && [[ -n "$HARDWARE_CONFIG_PATH" ]]; then
	CMD+=(--generate-hardware-config "$HARDWARE_CONFIG_GENERATOR" "$HARDWARE_CONFIG_PATH")
fi

"${CMD[@]}"
