#!/usr/bin/env bash
set -euo pipefail

BOOTSTRAP_CONFIG=""
TARGET_HOST=""
BOOTSTRAP_USER=""
FLAKE_TARGET=""
EXTRA_FILES=""
HARDWARE_CONFIG_GENERATOR=""
HARDWARE_CONFIG_PATH=""
SKIP_HARDWARE_CONFIG="false"

usage() {
	cat <<EOF
Usage: $0 [--host-config <path>] [--target <host-or-ip>] [--bootstrap-user <user>] [--flake <flake-ref>] [--extra-files <path>] [--hardware-config-generator <name>] [--hardware-config-path <path>] [--skip-hardware-config]

--host-config <path> is required; deploy.sh never assumes a default host. The
canonical caller is the just bootstrap recipe (just bootstrap <host> <addr>),
which resolves hosts/<host>/bootstrap-config.nix for the requested host and
passes it here.

The temporary installer image's SSH host key is diagnostic only: never derive
a persistent SOPS age recipient from it. Enroll the persistent recipient only
after first boot from the console-verified persistent host key (two-step
secrets bootstrap; see docs/runbooks/host-initialization.md).
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--host-config)
		if [[ $# -lt 2 ]]; then
			echo "Error: --host-config requires a value"
			exit 1
		fi
		BOOTSTRAP_CONFIG="$2"
		shift 2
		;;
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

eval_bootstrap_attr() {
	local attr="$1"
	nix eval --raw --file "$BOOTSTRAP_CONFIG" "$attr"
}

TARGET_HOST="$(normalize_prefixed_value target "$TARGET_HOST")"
BOOTSTRAP_USER="$(normalize_prefixed_value user "$BOOTSTRAP_USER")"
FLAKE_TARGET="$(normalize_prefixed_value flake "$FLAKE_TARGET")"
BOOTSTRAP_CONFIG="$(normalize_prefixed_value host_config "$BOOTSTRAP_CONFIG")"
EXTRA_FILES="$(normalize_prefixed_value extra_files "$EXTRA_FILES")"
HARDWARE_CONFIG_GENERATOR="$(normalize_prefixed_value hardware_config_generator "$HARDWARE_CONFIG_GENERATOR")"
HARDWARE_CONFIG_PATH="$(normalize_prefixed_value hardware_config_path "$HARDWARE_CONFIG_PATH")"

if [[ -z "$BOOTSTRAP_CONFIG" ]]; then
	echo "Error: --host-config is required; deploy.sh assumes no default host (use just bootstrap <host> <addr>)" >&2
	exit 1
fi

if [[ ! -f "$BOOTSTRAP_CONFIG" ]]; then
	echo "Error: bootstrap config not found: $BOOTSTRAP_CONFIG"
	exit 1
fi

if [[ -z "$TARGET_HOST" ]]; then
	TARGET_HOST="$(nix eval --raw --file "$BOOTSTRAP_CONFIG" hostName)"
fi

if [[ -z "$BOOTSTRAP_USER" ]]; then
	BOOTSTRAP_USER="$(nix eval --raw --file "$BOOTSTRAP_CONFIG" bootstrapUser)"
fi

if [[ -z "$FLAKE_TARGET" ]]; then
	FLAKE_TARGET="$(nix eval --raw --file "$BOOTSTRAP_CONFIG" flake)"
fi

# Hardware-config generation is opt-in and must be declared explicitly by the
# host config; there is no shared fallback path to assume.
if [[ -z "$HARDWARE_CONFIG_GENERATOR" ]] && grep -q '^  hardwareConfigGenerator' "$BOOTSTRAP_CONFIG"; then
	HARDWARE_CONFIG_GENERATOR="$(eval_bootstrap_attr hardwareConfigGenerator)"
fi

if [[ -z "$HARDWARE_CONFIG_PATH" ]] && grep -q '^  hardwareConfigPath' "$BOOTSTRAP_CONFIG"; then
	HARDWARE_CONFIG_PATH="$(eval_bootstrap_attr hardwareConfigPath)"
fi

if [[ "$SKIP_HARDWARE_CONFIG" != "true" ]] && { [[ -n "$HARDWARE_CONFIG_GENERATOR" ]] || [[ -n "$HARDWARE_CONFIG_PATH" ]]; }; then
	if [[ -z "$HARDWARE_CONFIG_GENERATOR" ]] || [[ -z "$HARDWARE_CONFIG_PATH" ]]; then
		echo "Error: $BOOTSTRAP_CONFIG must declare both hardwareConfigGenerator and hardwareConfigPath together (or pass --skip-hardware-config)" >&2
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
