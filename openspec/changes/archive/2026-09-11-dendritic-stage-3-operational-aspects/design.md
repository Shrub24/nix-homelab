# Dendritic Stage 3 — Operational Aspects Design

## Context

Stage 2 (FND-6) deferred five operational leaves as explicit raw-leaf imports in
every host record so their ownership could be resolved separately from the
foundation. Those leaves now have clear boundaries, scoped in
`docs/dendritic-transition-analysis.md` and confirmed by the proposal: backups
and cache upload form one host-egress capability, nixbuild SSH trust is builder
access, and Beszel agent enrollment is observability-agent capability. This
stage publishes `backups`, `builder-access`, and `observability-agent` as
explicit NixOS aspects, folds the five leaves under them, and removes the
repeated host import block and enablement those aspects replace.

The five deferred leaves, all imported by all three hosts today (proven by
`tests/check-dendritic-scaffold-contract.sh` 7g):

- `modules/services/state-backups.nix`
- `modules/shared/niks3-upload-client.nix`
- `modules/shared/niks3-post-deploy.nix`
- `modules/shared/nixbuild-ssh.nix`
- `modules/services/beszel-agent-auth.nix`

## Behavior IDs

| ID | Preserved or introduced composition behavior | Risk |
| --- | --- | --- |
| OPS-1 | Three public aspects published; selection is enablement | Medium |
| OPS-2 | All three current hosts select all three aspects | Medium |
| OPS-3 | Backups composes state-backups, niks3 client, and post-deploy; bucket derived from host name | High |
| OPS-4 | Notify owns monitor composition; backups asserts the monitor option; no transitive aspect import | Medium |
| OPS-5 | OCI niks3 token owner keeps `mkDefault` precedence | High |
| OPS-6 | `nix.settings.post-build-hook = mkForce ""` is classified as currently necessary | High |
| OPS-7 | Builder-access owns only nixbuild.net SSH trust | Low |
| OPS-8 | Observability-agent keeps the pathExists bootstrap gate and excludes the hub | Medium |
| OPS-9 | `services`/`shared` import-tree exclusions are unchanged | Low |
| OPS-10 | All three configurations remain evaluation-equivalent and revertible | High |
| OPS-11 | Derived bucket name is asserted valid S3 (3–63 lowercase alnum/hyphen) | Low |

## Decisions

### OPS-1 — Three public aspect boundaries/names

Publish exactly `backups`, `builder-access`, and `observability-agent` through
`flake.modules.nixos` in `modules/flake/aspects.nix`, beside the infra trio and
five foundation aspects. Each is an ordinary deferred module; selection is
enablement (FND-1 rule). The five deferred leaves fold under them:

| Leaf | Aspect |
| --- | --- |
| `modules/services/state-backups.nix` | `backups` |
| `modules/shared/niks3-upload-client.nix` | `backups` |
| `modules/shared/niks3-post-deploy.nix` | `backups` |
| `modules/shared/nixbuild-ssh.nix` | `builder-access` |
| `modules/services/beszel-agent-auth.nix` | `observability-agent` |

The `backups` aspect also imports the upstream
`inputs.niks3.nixosModules.niks3-auto-upload` module itself (OPS-3); the
registry records drop that import during implementation, and OCI keeps only the
niks3 server module import (`inputs.niks3.nixosModules.niks3`).

The boundary follows the transition analysis: `backups` is one coherent "state
leaves the host" story; `builder-access` is genuinely optional per host;
`observability-agent` is distinct from the hub and applies to every monitored
host. Each aspect may import its own private/plain NixOS leaf (the FND-1 rule);
no aspect imports another aspect. Leaves keep their option namespaces
(`services.state-backups`, `services.niks3-auto-upload`,
`services.niks3-post-deploy`, `services.beszel-agent-auth`) so host variant
declarations keep working unchanged.

### OPS-2 — All current hosts select all three

All three registry records (`oci-melb-1`, `la-admin-1`, `home-forge`) add
`aspects.backups`, `aspects.builder-access`, `aspects.observability-agent` to
their `module.imports` in canonical order and delete the five-leaf deferred
import block. This preserves today's state: all five leaves are imported by all
three hosts, and the proposal explicitly preserves all three current
selections, including builder access on home-forge.

The repeated enablement and host bindings are deleted with the block:

- `fleet.nixbuild-ssh.enable = true` ×3
- `services.niks3-post-deploy.enable = true` ×3
- `services.state-backups.enable = true` ×3 (including home-forge's
  `lib.mkIf hasHostSecrets` wrapper — the gate generalizes into the aspect, OPS-3)
- `services.state-backups.secretFile` host bindings ×3 (derived by the aspect, OPS-3)
- `services.beszel-agent-auth.enable = true` ×3 (inside `lib.mkIf hasHostSecrets`)
- `services.beszel-agent-auth.secretFiles.host` host bindings ×3 (derived by the aspect, OPS-8)
- `inputs.niks3.nixosModules.niks3-auto-upload` registry import ×3 (moved into
  the `backups` aspect, OPS-3; OCI keeps `inputs.niks3.nixosModules.niks3`)

Selection is enablement: the aspect owns the enable. The transition analysis's
"forge may never get it" note for builder access is superseded: all three
hosts, including home-forge, select `builder-access` (proposal constraint).

### OPS-3 — Backups composes state-backups, niks3 client, and post-deploy

`backups` imports the three leaves plus the upstream
`inputs.niks3.nixosModules.niks3-auto-upload` module itself, and owns:

- `services.state-backups.enable = true`
- `services.niks3-auto-upload.enable = mkDefault true` (already in the client leaf, unchanged)
- `services.niks3-post-deploy.enable = true`
- bucket derivation: `services.state-backups.bucket = lib.mkDefault "shrublab-backup-${config.networking.hostName}"`, replacing the three host literals (`shrublab-backup-oci-melb-1`, `shrublab-backup-la-admin-1`, `shrublab-backup-home-forge`) which all equal the convention exactly.

The aspect derives the conventional host secret path
`secrets/hosts/${config.networking.hostName}/system.yaml`, defaults
`services.state-backups.secretFile` to it, and gates the state-backups and
post-deploy enablement on `builtins.pathExists` of that file. The client leaf
already gates itself on the same conventional path (OPS-5), so the whole
host-egress capability activates only when host secrets exist on every host.
This generalizes home-forge's current `lib.mkIf hasHostSecrets` gate to all
three hosts: OCI and LA are unchanged because their files exist, and a fresh
host evaluates safely and activates after the operator adds host secrets
(two-step bootstrap preserved). The three host `secretFile` bindings are
removed — the derived default is the only value.

The aspect also injects the required post-deploy filter package: it resolves
`nix-path-filter` per system via `withSystem` (analogous to `notify`) and sets
the new required typed option `services.niks3-post-deploy.filterPackage`
(`lib.types.package`, no default and no nixpkgs fallback). The post-deploy leaf
reads `cfg.filterPackage` instead of `config.repo.packages.nix-path-filter`, so
`backups` has no hidden `fleet-packages` dependency.

Hosts retain real variants only:

- `state-backups.stagingRoot` (oci, forge; la uses the module default)
- forge's `state-backups.services.host-core.paths = [ "/etc/ssh" ]` backup contract
- OCI's loopback `niks3-auto-upload.serverUrl = "http://127.0.0.1:5751"` override

The client leaf keeps its pathExists gate and `mkDefault` token registration
(OPS-5); the post-deploy leaf keeps its `mkForce ""` (OPS-6). The aspect adds
an eval assertion that the derived bucket name matches the S3 3–63 lowercase
alnum/hyphen rule (OPS-11).

### OPS-4 — Notify owns monitor composition; backups asserts the monitor option

The canonical apprise-notification contract (the notify aspect guarantees
daemon and monitor composition) is implemented by moving
`services.notification-daemon.monitor.enable = true` into the existing `notify`
aspect; the `mkDefault true` assignment is removed from the state-backups leaf.
The leaf keeps only the `svc-monitor@restic-backups-state.service` OnFailure
wiring, which now resolves against the notify-owned monitor template.

`backups` does NOT import `notify` — explicit selection plus assertion, never
hidden transitive imports. The aspect asserts the actual monitor dependency
with `lib.attrByPath [ "services" "notification-daemon" "monitor" "enable" ] false config`,
which both checks the real svc-monitor option and yields the named assertion
when `notify` is absent (the option is unset → false). A future host that
selects backups without notify fails eval with a named message instead of
silently missing its failure-monitoring template.

### OPS-5 — OCI token owner keeps `mkDefault` precedence

The niks3 client leaf registers `niks3_api_token` with all-`mkDefault` values
and no owner/group (root:root default). The OCI cache-server module
(`modules/services/niks3.nix`) re-registers the same secret with explicit
`owner = "niks3"; group = "niks3"` (no `mkDefault`), which wins over the
client's `mkDefault` record. The `backups` aspect preserves this exact
precedence: the token registration stays `mkDefault` in the client leaf, OCI's
explicit owner/group continues to win, and OCI's host override
`niks3-auto-upload.serverUrl = "http://127.0.0.1:5751"` stays. No `mkForce` is
introduced anywhere.

### OPS-6 — `post-build-hook = mkForce ""` is classified, not removed

Upstream `niks3-auto-upload.nix` sets
`nix.settings.post-build-hook = toString postBuildHookScript` whenever
`services.niks3-auto-upload.enable` is true — which it is on all deployed hosts
via the client leaf's `enable = mkDefault true`. The repo's post-deploy leaf
sets `nix.settings.post-build-hook = lib.mkForce ""` because the fleet
deliberately does not run the hook on every Nix build: post-deploy closure
upload is activation-triggered (`system.activationScripts.niks3-post-deploy` →
`niks3-hook send`) against the same daemon/socket the upstream module creates.

The `mkForce ""` is therefore currently necessary: it suppresses the upstream
automatic hook while reusing the upstream daemon/socket for the
activation-triggered send. Moving or removing it (an upstream option to disable
the hook, or splitting the daemon from the hook) is a separate upstream/interface
redesign and is out of scope. The existing `mkForce ""` is classified in the
`backups` aspect and retained; no new `mkForce` is added.

### OPS-7 — Builder-access is trust-only

`builder-access` owns only nixbuild.net SSH trust: `programs.ssh.knownHosts.nixbuild`
and `programs.ssh.extraConfig` for `eu.nixbuild.net`. Substituter policy
(nixbuild.net in `nix.settings` substituters) remains in the `base` aspect —
the aspect does not touch it. The `fleet.nixbuild-ssh.enable` option is retired
with its three host declarations (no external consumer remains; the aspect's
selection is the enablement). The leaf's config becomes unconditional under the
aspect, or the aspect sets the enable internally — implementation choice.

### OPS-8 — Observability-agent derives the host secret path and gates on it

`observability-agent` owns Beszel agent authentication and enrollment: the
`beszel-agent-auth` leaf's sops templates, secret registrations, and
`services.beszel.agent.enable`. The aspect derives the conventional host secret
path `secrets/hosts/${config.networking.hostName}/system.yaml`, sets
`services.beszel-agent-auth.secretFiles.host` to it, and gates the leaf's
enablement on `builtins.pathExists` of that path. The three host
`secretFiles.host` bindings and their `lib.mkIf hasHostSecrets` wrappers are
removed — the aspect owns the gate for every host, preserving the two-step
bootstrap exactly as hosts declare it today: a fresh host evaluates without the
file and enrolls after the operator adds host secrets.

The Beszel hub (`services.beszel.hub` in `modules/services/admin/beszel.nix`)
remains an admin-service leaf: the aspect neither imports nor enables it, and
the hub's state-backup contract (`services.state-backups.services.beszel`) stays
in the admin leaf.

### OPS-9 — No import-tree exclusion shrink

`modules/flake/_unconverted-nixos-dirs.nix` keeps `services` and `shared`
excluded: both roots still contain unconverted leaves (`web-policy.nix`,
`kanidm-host-auth.nix`, `identity-oidc.nix` in shared; the service tree still
has many plain leaves). The five converted leaves move under their aspects but
the directories stay excluded. The scaffold contract's exact-list checks are updated to reflect the new aspect
publication (7a), the canonical eight-aspect registry block (7b), and the
replacement of the retained-leaf check with aspect-selection checks (7g) — the
exclusion list itself is unchanged.

### OPS-10 — All three configurations remain evaluation-equivalent and revertible

Same gate as FND-7: capture each host toplevel derivation and targeted values
before the change; after the change, `nix-diff` must be empty or every delta
classified line-by-line with targeted option comparisons proving runtime
equivalence. Rollback is a revert of the single JJ change.

## Host responsibility migration

| Responsibility today | Stage 3 location |
| --- | --- |
| `shared/niks3-post-deploy.nix` import + `services.niks3-post-deploy.enable = true` ×3 | `backups` aspect (imports the leaf, owns enablement gated on the conventional host secret path) |
| `shared/niks3-upload-client.nix` import ×3 | `backups` aspect (imports the leaf; leaf keeps `mkDefault` client defaults, pathExists gate, token registration) |
| `services/state-backups.nix` import + `enable = true` ×3 + bucket literals ×3 + home-forge `lib.mkIf hasHostSecrets` gate | `backups` aspect (imports the leaf, owns enablement gated on the conventional host secret path, derives bucket `shrublab-backup-${networking.hostName}`) |
| `state-backups.secretFile` host bindings (all three) | Removed; `backups` derives `secrets/hosts/${networking.hostName}/system.yaml` and defaults `secretFile` to it (OPS-3) |
| `state-backups.stagingRoot` (oci, forge) | Host records keep the staging-root variant |
| `state-backups.services.host-core.paths = [ "/etc/ssh" ]` (forge) | Host record keeps the backup contract |
| `niks3-auto-upload.serverUrl = "http://127.0.0.1:5751"` (oci) | Host record keeps the loopback override |
| `inputs.niks3.nixosModules.niks3-auto-upload` registry import ×3 | Removed from registry records; `backups` imports the upstream module itself (OPS-3); OCI keeps `inputs.niks3.nixosModules.niks3` |
| `config.repo.packages.nix-path-filter` read (post-deploy leaf) | Replaced by required typed `services.niks3-post-deploy.filterPackage` injected per-system by `backups` via `withSystem` (OPS-3) |
| `shared/nixbuild-ssh.nix` import + `fleet.nixbuild-ssh.enable = true` ×3 | `builder-access` aspect (imports the leaf, owns enablement; option retired) |
| `services/beszel-agent-auth.nix` import + `enable = true` inside `lib.mkIf hasHostSecrets` ×3 | `observability-agent` aspect (imports the leaf, owns enablement and the pathExists gate) |
| `beszel-agent-auth.secretFiles.host` bindings ×3 | Removed; `observability-agent` derives `secrets/hosts/${networking.hostName}/system.yaml` (OPS-8) |
| Beszel hub (`services/admin/beszel.nix`) | Unchanged admin-service leaf; not part of the aspect |
| `nix.settings.post-build-hook = mkForce ""` (post-deploy leaf) | Retained in the `backups` aspect, classified (OPS-6) |
| `notification-daemon.monitor.enable = mkDefault true` (state-backups leaf) | Moved to the `notify` aspect (canonical apprise contract); leaf keeps only the OnFailure wiring; `backups` asserts the monitor option via attrByPath (OPS-4) |

## Non-goals and boundaries

- No edits to encrypted secrets, `.sops.yaml`, recipient policy, deployment
  topology/order, bootstrap metadata, or `specialArgs` (removed in Stage 1).
- No conversion of the niks3 server, Beszel hub, admin/identity/music/product
  aspects, or the remaining shared/service leaves (`web-policy`,
  `kanidm-host-auth`, `identity-oidc`, and the rest of the service tree).
- No hidden aspect imports, compatibility aspect, generic composition bus, or
  new `mkForce`.
- No rename of the `backups` aspect: it is established project terminology for
  the broader state-egress/cache-upload capability (transition analysis row 10).
- No hidden `fleet-packages` dependency: `backups` injects its own required
  package input (OPS-3).
- Historical runbook bucket literals (`shrublab-backup-<host>` in
  `docs/runbooks/state-restore.md` and `docs/architecture.md`) remain
  historical documentation of the actual bucket names; they are not rewritten.
- No import-tree exclusion shrink (OPS-9).
- No upstream `niks3-auto-upload` interface change (OPS-6).

## Baseline and equivalence

1. Capture each host toplevel derivation and targeted values: state-backups
   (bucket, stagingRoot, secretFile, restic job, tmpfiles, OnFailure),
   niks3-auto-upload (enable, serverUrl, authTokenFile, socket, daemon unit),
   the `niks3_api_token` secret record (sopsFile, key, path, owner, group,
   mode), `nix.settings.post-build-hook`, the niks3-post-deploy activation
   script and unit, nixbuild SSH knownHosts/extraConfig, and the beszel agent
   env template, secrets, and unit.
2. Add the three aspect definitions and move the leaves; change every host
   registry import list (dropping `inputs.niks3.nixosModules.niks3-auto-upload`),
   and delete the five-leaf block, the repeated enablement, and the host
   `secretFile`/`secretFiles.host` bindings in one working change.
3. Delete legacy host declarations only after the new evaluated values match.
4. Run the updated dendritic scaffold contract, backup-surface contract,
   secret-scope check, formatter check, and the canonical
   `nix flake check --no-build --no-write-lock-file --refresh path:.` gate.
5. Evaluate all three target systems and run `nix-diff` against the Stage 2
   baseline. Any derivation delta must be classified line-by-line; changed
   source/provenance alone is acceptable only when the targeted option
   comparisons prove runtime equivalence.

## Staged migration

One working change (anonymous JJ change on `main@origin`), same as Stage 2.
There is no deployment, disk migration, secret migration, or data migration in
this change.

## Rollback

Revert the single JJ change and re-run the same evaluation checks. No runtime
state is touched.

## Risks

- **Bucket derivation changes a restic repository target** — the derived value
  must equal the three existing literals exactly; assert equality in the
  scaffold contract before deleting the literals.
- **`mkDefault` token precedence flips** — compare the evaluated
  `niks3_api_token` record (owner/group) on OCI before/after; the cache
  server's explicit owner must win.
- **`post-build-hook` `mkForce ""` removed or re-prioritized** — keep the
  classified `mkForce ""` in the `backups` aspect; verify
  `nix.settings.post-build-hook` evaluates to `""` on all hosts.
- **Notify assertion fires on a host that selects backups without notify** —
  all current hosts select `notify` (foundation), so the assertion is a
  future-host guard; verify it passes on all three.
- **pathExists gate changes bootstrap behavior** — the observability-agent gate
  must use the same pathExists condition hosts use today; compare evaluated
  beszel agent config on a host without secrets (fresh eval) before/after.
- **A direct raw leaf is omitted while deleting the five-leaf block** —
  inventory every old import/configuration responsibility against the
  migration table and evaluate all hosts before deletion.
- **Import-tree discovers a converted leaf** — the leaves move under aspects
  but `services`/`shared` stay excluded (OPS-9); the scaffold contract pins the
  exact list.
- **Bucket-name validity assertion fires** — the derived
  `shrublab-backup-${hostName}` must match the 3–63 lowercase alnum/hyphen S3
  rule; all three host names do, and the scaffold contract pins a focused
  negative test (OPS-11).
- **pathExists gate changes post-deploy behavior on a fresh host** — post-deploy
  enablement is now gated on the conventional host secret path; OCI/LA files
  exist so nothing changes, and a fresh host skips post-deploy until secrets
  exist (safe bootstrap).
- **Monitor ownership move breaks a host that sets `monitor.enable` explicitly**
  — OCI already sets `monitor.enable = true`; the `notify` aspect's `enable =
  true` is consistent; verify all three hosts evaluate with the monitor option
  true (OPS-4).

## Docs and tests

- Update `docs/architecture.md` (backup, cache-upload, builder-trust, and
  Beszel ownership sections), `docs/decisions.md` (new decision recording
  OPS-1–OPS-11, superseding the FND-6 deferred-leaf rows for these five
  leaves), `docs/plan.md` (Track E stage-3 progress), `docs/context-history.md`,
  and `docs/dendritic-transition-analysis.md` (Stage 3 status note; mark the
  "forge may never get it" builder-access claim superseded — all three hosts,
  including home-forge, select `builder-access`).
- Update `tests/check-dendritic-scaffold-contract.sh`:
  - 7a: the publication list gains `backups`, `builder-access`, and
    `observability-agent` (eleven aspects total).
  - 7b: the canonical registry block becomes the eight-aspect block ×3
    (`base`, `shell`, `networking`, `tailscale`, `notify`, `backups`,
    `builder-access`, `observability-agent`).
  - 7g: the retained-leaf check is replaced by aspect-selection checks (all
    three hosts select all three aspects; hosts no longer import the five
    leaves directly or the `niks3-auto-upload` upstream module; the leaves are
    now drawn into aspects).
  - Add observable probes for the three aspects (backups bucket derivation and
    pathExists gate, builder SSH trust, beszel agent gate).
  - Add a negative notify mutation: a controlled mutation that removes `notify`
    from a host's registry selection must fail with the named monitor
    assertion (OPS-4).
  - Add a focused negative test for the bucket-name validity assertion: a
    derived name outside the 3–63 lowercase alnum/hyphen rule must fail eval
    (OPS-11).
- Historical runbook bucket literals (`shrublab-backup-<host>` in
  `docs/runbooks/state-restore.md` and `docs/architecture.md`) remain
  historical documentation of the actual bucket names and are not rewritten;
  the derived convention equals them exactly.
- `tests/check-backup-surface-contract.sh` stays green (the
  `state-restore-stage` helper is unchanged).
- `tests/check-secret-scope.sh` stays green (no ciphertext or readership
  change).
- `just backups run/status/logs/restore-stage` recipes are unchanged.

## Unresolved questions

None requiring user input. The exact private-leaf placement (aspect imports the
existing leaf file versus relocating the leaf under an aspect-owned directory)
is an implementation choice: use the shorter form that preserves the public
aspect and import contracts, matching the FND-1 rule.