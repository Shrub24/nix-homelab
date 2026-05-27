set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

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
deploy host="oci-melb-1" rollback="true":
    @HOST="{{ host }}"; ROLLBACK="{{ rollback }}"; EXIT=0; \
    if [[ -z "$HOST" ]]; then echo "Error: host required (use --host <nixosConfiguration>)"; exit 1; fi; \
    ARGS=(--skip-checks); \
    [[ "$ROLLBACK" != "false" ]] || ARGS+=(--auto-rollback false); \
    nix run .#deploy-rs -- "${ARGS[@]}" ".#$HOST" || EXIT=$?; \
    if [ "$EXIT" -eq 0 ]; then \
        printf 'deploy-rs succeeded for %s' "$HOST" | nix run .#notify -- info "Deploy $HOST" deploy system; \
    else \
        printf 'deploy-rs failed for %s (exit %d)' "$HOST" "$EXIT" | nix run .#notify -- warning "Deploy $HOST" deploy system; \
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

_build host="oci-melb-1":
    @nix build --no-link --no-write-lock-file "path:.#nixosConfigurations.{{ host }}.config.system.build.toplevel"

prebuild host="oci-melb-1":
    @nix build \
        --no-link \
        --no-write-lock-file \
        --print-build-logs \
        --eval-store auto \
        --store "ssh-ng://eu.nixbuild.net" \
        "path:.#nixosConfigurations.{{ host }}.config.system.build.toplevel"

# Cross-cutting repo orchestration
mod ops '.just/ops.just'
mod checks '.just/checks.just'
mod backups '.just/backups.just'
mod host-age '.just/host-age.just'
mod dev '.just/dev.just'

# Domain-colocated modules
mod tofu 'opentofu'
mod secrets 'secrets'
