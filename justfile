set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

# Format all non-excluded files across the repo
fmt:
    treefmt

# Check formatting without modifying files
fmt-check:
    treefmt --fail-on-change

bootstrap host target:
    @TARGET="{{ target }}"; \
    echo "Checking port 22 on $TARGET..."; \
    if ! nc -z -w5 "$TARGET" 22 2>/dev/null; then \
        echo "Error: port 22 is not reachable on $TARGET"; \
        echo "Ensure the target is running and tcp/22 is open before bootstrapping."; \
        exit 1; \
    fi; \
    echo "Port 22 is open on $TARGET."; \
    source scripts/resolve-host-config.sh "{{ host }}"; \
    ./deploy.sh \
        --host-config "$HOST_CONFIG" \
        --target "{{ target }}" \
        --bootstrap-user "$BOOTSTRAP_USER" \
        --flake "$FLAKE" \
        "$@"

[arg("rollback", long="rollback")]
[arg("verbose", long="verbose")]
deploy host="la-admin-1" rollback="true" verbose="false":
    @HOST="{{ host }}"; ROLLBACK="{{ rollback }}"; VERBOSE="{{ verbose }}"; EXIT=0; \
    if [[ -z "$HOST" ]]; then echo "Error: host required (use --host <nixosConfiguration>)"; exit 1; fi; \
    STRICT="$(nix eval --raw --no-write-lock-file --apply 'value: if value then "true" else "false"' "path:.#deployHosts.nodes.\"$HOST\".strictSubstituteOnly")"; \
    ARGS=(--skip-checks); \
    NIX_ARGS=(); \
    [[ "$ROLLBACK" != "false" ]] || ARGS+=(--auto-rollback false); \
    if [[ "$VERBOSE" == "true" ]]; then ARGS+=(--debug-logs); fi; \
    if [[ "$STRICT" == "true" || "$VERBOSE" == "true" ]]; then \
        NIX_ARGS=(--); \
        if [[ "$STRICT" == "true" ]]; then NIX_ARGS+=(--option max-jobs 0 --option builders ""); fi; \
        if [[ "$VERBOSE" == "true" ]]; then NIX_ARGS+=(-v); fi; \
    fi; \
    nix run .#deploy-rs -- "${ARGS[@]}" ".#$HOST" "${NIX_ARGS[@]}" || EXIT=$?; \
    if [ "$EXIT" -eq 0 ]; then \
        printf 'deploy-rs succeeded for %s' "$HOST" | nix run .#notify -- info "Deploy $HOST" deploy system || true; \
    else \
        printf 'deploy-rs failed for %s (exit %d)' "$HOST" "$EXIT" | nix run .#notify -- warning "Deploy $HOST" deploy system || true; \
    fi; \
    exit "$EXIT"

host host:
    @nix run .#deploy-rs -- --skip-checks ".#{{ host }}"

_preflight host:
    @HOST="{{ host }}"; \
    nix eval --no-write-lock-file --apply 'cfg: if cfg.services.openssh.enable then true else throw "openssh is disabled"' "path:.#nixosConfigurations.${HOST}.config" >/dev/null; \
    nix eval --no-write-lock-file --apply 'cfg: let ports = cfg.networking.firewall.allowedTCPPorts or [ ]; in if builtins.elem 22 ports then true else throw "firewall does not allow tcp/22"' "path:.#nixosConfigurations.${HOST}.config" >/dev/null; \
    nix eval --no-write-lock-file --apply 'cfg: let devKeys = cfg.users.users.dev.openssh.authorizedKeys.keys or [ ]; rootKeys = cfg.users.users.root.openssh.authorizedKeys.keys or [ ]; in if (builtins.length devKeys > 0) && (builtins.length rootKeys > 0) then true else throw "missing declarative dev/root SSH keys"' "path:.#nixosConfigurations.${HOST}.config" >/dev/null; \
    echo "preflight PASS: ${HOST} (openssh, tcp/22, dev+root keys)"

_activate host:
    @HOST="{{ host }}"; \
    if [[ -z "$HOST" ]]; then echo "Error: host required"; exit 1; fi; \
    nix run .#deploy-rs -- --skip-checks --dry-activate ".#$HOST"

_build host="la-admin-1":
    @nix build --no-link --no-write-lock-file ".#deploy.nodes.{{ host }}.profiles.system.path"

# Run nh clean all on a host (manual GC trigger)
nh-clean host="oci-melb-1":
    @ssh "{{ host }}" "nh clean all --keep 3"

prebuild-remote host="oci-melb-1":
    @nix build \
        --no-link \
        --no-write-lock-file \
        --print-build-logs \
        --eval-store auto \
        --store "ssh-ng://eu.nixbuild.net" \
        ".#host-{{ host }}"

# Build a host config locally, then push the full closure to cache.
prebuild-local host="la-admin-1":
    @BUILD_DIR=$(mktemp -d); trap 'rm -rf "$BUILD_DIR"' EXIT; \
    nix build \
        --out-link "$BUILD_DIR/result" \
        --no-write-lock-file \
        --print-build-logs \
        ".#host-{{ host }}"; \
    RESULT=$(readlink -f "$BUILD_DIR/result"); \
    OUT_PATHS=$(nix run .#nix-path-filter -- "$RESULT" | tr '\n' ' ') \
    niks3-hook send --socket=/run/user/1000/niks3-upload-to-cache.sock

# Cross-cutting repo orchestration
mod ops '.just/ops.just'
mod checks '.just/checks.just'
mod backups '.just/backups.just'
mod host-age '.just/host-age.just'
mod deps '.just/deps.just'
mod dev '.just/dev.just'

# Domain-colocated modules
mod tofu 'opentofu'
mod secrets 'secrets'
