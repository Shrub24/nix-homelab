## Runner Parity (from beets-interactive-runner-parity)

### 1. Beets Config Semantics

- [x] 1.1 Add explicit `/srv/media/library` destination to standard and quarantine Beets configs.
- [x] 1.2 Change quarantine config to retry-friendly unresolved handling and remove automatic conversion from the quarantine path.

### 2. Runner Parity

- [x] 2.1 Update `beets-runner-quarantine-interactive` to perform media checks, settle checks, interactive import, leftover demotion, and log cleanup like the normal runner.
- [x] 2.2 Ensure the quarantine interactive runner has required runtime tools for checks/demotion without adding ffmpeg conversion.

### 3. Wrapper Logging and Post Actions

- [x] 3.1 Update `beets-interactive` to use a predictable transient systemd unit name and journal mode that captures useful stdout/stderr.
- [x] 3.2 Run permission reconciliation and trigger `navidrome-scan.service` after successful interactive imports.

### 4. Validation

- [x] 4.1 Run `nix-instantiate --parse` on modified Nix files.
- [x] 4.2 Run `treefmt --fail-on-change` on modified files.
- [x] 4.3 Run `openspec validate --strict beets-interactive-runner-parity`.
- [x] 4.4 Run scoped evaluation for the generated wrapper/unit behavior where feasible.

## Navidrome Scan Hook (from beets-navidrome-scan-hook)

### 1. Navidrome Scan Unit

- [x] 1.1 Add a `navidrome-scan.service` oneshot unit in `modules/services/music/navidrome.nix` using the configured Navidrome package, data folder, and music folder.
- [x] 1.2 Ensure the scan unit runs with Navidrome user/group, required supplementary media groups, and mount prerequisites.

### 2. Beets Inbox Success Chain

- [x] 2.1 Remove the over-complex Beets import item-count hook, post-success command option, marker file scripts, and privileged marker consumer.
- [x] 2.2 Wire `beets-inbox.service` to `navidrome-scan.service` with systemd `OnSuccess=` in the application composition layer.

### 3. Validation

- [x] 3.1 Run `nix-instantiate --parse` on modified Nix files.
- [x] 3.2 Run `treefmt --fail-on-change` on modified files.
- [x] 3.3 Run `openspec validate --strict beets-navidrome-scan-hook`.
- [x] 3.4 Run scoped Nix evaluation or `nix flake check --no-build`, noting any unrelated pre-existing blocker.

## Permission Reconciliation Extraction (from extract-permission-reconcile)

### 1. Standalone Permission Reconcile Service

- [x] 1.1 Create `media-permission-reconcile.service` in `modules/applications/music/default.nix` as a root oneshot with the existing ACL fixup logic.
- [x] 1.2 Create `media-fixperms` CLI wrapper that runs `systemctl start media-permission-reconcile.service`.

### 2. Remove from Beets Framework

- [x] 2.1 Remove `permission-reconcile` from the `runnerKind` enum in `modules/services/music/beets/default.nix`.
- [x] 2.2 Remove the `permission-reconcile` entry from `modules/services/music/beets/runners.nix`.
- [x] 2.3 Remove `permissionReconcileBin` let-binding and `ExecStartPost` usage in `modules/services/music/beets/default.nix`.
- [x] 2.4 Remove the `permission-reconcile` runner instance from `modules/applications/music/default.nix`.
- [x] 2.5 Remove the old `beets-fixperms` wrapper.

### 3. Wire OnSuccess Chaining

- [x] 3.1 Add `OnSuccess = [ "media-permission-reconcile.service" ]` to beets runner services in the beets module.
- [x] 3.2 Update `beets-interactive` wrapper to call `systemctl start media-permission-reconcile.service` instead of `beets-permission-reconcile.service`.

### 4. Validation

- [x] 4.1 Run `nix-instantiate --parse` on modified Nix files.
- [x] 4.2 Run `treefmt --fail-on-change` on modified files.
- [x] 4.3 Run `openspec validate --strict extract-permission-reconcile`.
- [x] 4.4 Run scoped eval confirming `media-permission-reconcile.service` exists and runs as root.

## Convert Plugin Removal (from remove-beets-convert-plugin)

### 1. Remove Convert Plugin

- [x] 1.1 Remove `convert` from the plugin list in `beets-config.yaml`.
- [x] 1.2 Remove the `convert:` configuration block from `beets-config.yaml`.

### 2. Validation

- [x] 2.1 Run `treefmt --fail-on-change` on modified files.
- [x] 2.2 Run `openspec validate --strict remove-beets-convert-plugin`.
