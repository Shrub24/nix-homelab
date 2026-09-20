# Stage 8 baseline — preconditions and captured starting state

Captured for `dendritic-stage-8-host-identity-contracts` tasks 1.1 and 1.2. **Capture only**: no
product code was edited by this run (new file: this baseline; plus the two task checkboxes).

Raw evidence: `/tmp/nix-homelab-stage8-evidence/` (`probe.nix`, `<host>.observables.json` +
`.rc`/`.err`, `<host>.drvPath.txt`, `flake-bootstrap-nodes.json`, `deploy-hosts.json`).

---

## 1.1 Preconditions

### Prerequisite changes

| Change | State | Evidence |
|---|---|---|
| `decouple-identity-admin-capabilities` | **implemented + archived** | `openspec/changes/archive/2026-09-18-decouple-identity-admin-capabilities/` |
| `feature-owned-service-monitoring` | **implemented + archived** | `openspec/changes/archive/2026-09-18-feature-owned-service-monitoring/` |
| `split-state-backups-cache-publication` (Stage 8's direct prerequisite, D-055) | **implemented, NOT archived** | change folder still active at `openspec/changes/split-state-backups-cache-publication/`; 9/9 tasks checked; `openspec validate … --strict` valid |

**Deviation from the task brief:** the brief expected both prerequisites to show archive dirs.
`split-state-backups-cache-publication` is complete and validated but the operator has not archived
it yet, so no `archive/…-split-state-backups-cache-publication/` directory exists. Its *effect* on
the tree is present and is what this baseline captures (`modules/flake/state-backups.nix`,
`modules/flake/cache-publisher.nix`, four-host selection split). Archiving it is an OpenSpec
bookkeeping step, not a Stage 8 blocker.

### Revision chain (actual, verified via `jj log -r 'twuplskl::@'`)

| Role | Change ID | Commit ID | Description | Bookmark |
|---|---|---|---|---|
| working copy `@` | `npmrwnknoyuq` | `9fcacd0e` | `feat(ops): add Windows VM USB attach and detach commands` | — |
| `@-` | `zwltwwunmuxz` | `72f016ec` | `planning: split state backups and cache publication aspects` (D-055) | — |
| `@--` | `vqylpuvwvrko` | `962da197` | `refactor: decouple identity and admin capabilities` (D-054) | `wip/dendritic-transition*` |
| tested Stage 7 base | `twuplsklyllz` | `ee7780de` | `fix: make service monitoring feature-owned` | `wip/dendritic-transition@origin` |

**Deviation from the task brief:** the brief stated `@ = mxknyqsp (clean child)`. Actual working
copy is `npmrwnkn`/`9fcacd0e` with a **dirty working copy** (25 entries). `mxknyqspnzlpmlozrmomryxnrwklyokq`
/ `22018e03` (`feat(dendritic): stage 8 host identity and internal contracts`) exists but is **not
checked out** — it is an empty change, sibling to the current working copy, and holds no content.
The operator moved the working copy back to `npmrwnkn` after that change was created.

### Working-copy dirty set, classified

`jj st` (diff of `@` = `npmrwnkn` vs `@-` = `zwltwwun`) — 25 entries:

**Expected sibling content (user's concurrent work, out of Stage 8 scope):**
- `.just/ops.just` (M) + `openspec/changes/windows-vm-usb-ops/**` (5 files, A) — the Windows VM USB
  change the brief named.

**Split/D-055 residue not yet folded into a commit (in Stage 8's own dependency chain):**
- `modules/flake/cache-publisher.nix` (2 lines — final assertion-message fix)
- `tests/check-dendritic-scaffold-contract.sh` (51 lines — subset-isolation gate block)
- `tests/check-identity-contract-directionality.sh` (3 lines — operational-aspect expectation list)
- `openspec/changes/split-state-backups-cache-publication/tasks.md`
- `ARCHITECTURE.md`, `CONVENTIONS.md`, `STRUCTURE.md`, `docs/{architecture,context-history,decisions,dendritic-transition-analysis,plan}.md`

**Unrelated to either change — concurrent music/navidrome feature edits (flagged, not Stage 8 scope):**
- `modules/flake/music.nix` (2 lines), `modules/services/music/navidrome.nix` (28 lines),
  `modules/services/music/storage.nix` (8 lines). These correspond to the separate active OpenSpec
  changes `navidrome-m3u-itunes-worker` / `traktor-m3u-sync-worker`. They are feature-module edits,
  not deployment metadata, but they are present in the tree that this baseline evaluated. Stage 8
  implementation should either land or isolate them before starting, so the "no unrelated
  uncommitted edits" precondition holds for the implementation batch.

**OpenSpec structural repair (this run's predecessor, uncommitted; no evaluation impact):**
- `openspec/specs/{audiomuse-navidrome-similarity,operations,phoenix-otel-collector,postgres-shared-access}/spec.md`

### No unrelated uncommitted *deployment* edits — verified

Stage 8's own migration surfaces are **clean** in the working copy (absent from `jj st`):
`modules/flake/registry.nix`, `lib/deploy/hosts.nix`, `policy/web-services.nix`, `lib/policy.nix`,
`modules/flake/_unconverted-nixos-dirs.nix`, and every file under `modules/hosts/**`. Baseline
observables for host identity, deploy metadata, and web policy therefore describe committed content.

---

## 1.2 Baseline capture

### 1.2.1 Flake outputs, bootstrap, deploy metadata

- `nixosConfigurations` keys: `["home-forge","la-admin-1","oci-melb-1"]`.
- `bootstrap.nodes` keys: `["oci-melb-1"]` only. oci record:
  `{bootstrapDisk=/dev/sda, bootstrapUser=ubuntu, dataRoot=/srv/data, flake="path:.#oci-melb-1", hostName=oci-melb-1, mediaDisk=/dev/sdb, rootPartitionSize=20G}`.
  `hostName` and `flake` are derived from the registry key (`registry.nix:196-204`), not stored.
- Deploy metadata (`lib/deploy/hosts.nix`, raw JSON in `deploy-hosts.json`):

| Node | hostName | sshUser | system | remoteBuild | extra |
|---|---|---|---|---|---|
| `oci-melb-1` | `oci-melb-1` | `dev` | `aarch64-linux` | `true` | `strictSubstituteOnly=false` |
| `la-admin-1` | `la-admin-1` | `dev` | `x86_64-linux` | `false` | `bootstrapHostName=216.75.75.168`, `hostKeyFingerprint=SHA256:g71ri368dh+EkeJgXrHmMsrxlkwHI2T9G8rFD+G6fWw` |
| `home-forge` | `home-forge` | `dev` | `x86_64-linux` | `true` | `strictSubstituteOnly=false` |

- `edgeHost = "la-admin-1"`; `deployOrder = ["la-admin-1" "oci-melb-1"]` (home-forge is intentionally
  outside the serial order).
- **Finding:** the `deployment` option root is **absent** from all three host configurations
  (`deploymentOptionRootPresent=false` on every host). Deploy metadata is a flake-level concern fed
  from `lib/deploy/hosts.nix`, not per-host NixOS config — Stage 8 task 3.1 must keep it that way and
  may not look for `config.deployment.targetHost` in host evaluation.

### 1.2.2 Web host references

- `policy/web-services.nix` declares exactly **one** host key: `hosts.la-admin-1` (line 36). The
  other two hosts appear only as **local FQDN literals** at the top of the file:
  `oci = "oci-melb-1.tail0fe19b.ts.net"` (line 2), `homeForge = "home-forge.tail0fe19b.ts.net"` (line 3),
  consumed as `origin.host` of remote-upstream services (e.g. `navidrome.origin.host = homeForge`).
- `lib/policy.nix` consumes them via `policy.hosts.${hostName}` with a **throw** for unknown hosts
  (line 5: `throw "Unknown host '${hostName}' in policy/web-services.nix"`), and exposes
  `resolveHostServices` (line 36) and `resolveCloudflareHosts` (line 70); `servicesForHost`/
  `pickCanonicalService` (lines 99-101) and the export/route maps (lines 120, 136-156, 180-187)
  build catalog/routes/ports from them.
- Evaluated web output per host (`repo.web`):
  - `repo.web.catalog` — 20 service keys, identical on all three hosts: `admin-homepage`,
    `beszel-admin`, `bifrost`, `cockpit-admin`, `cockpit-oci-melb-1`, `gatus-admin`, `kanidm-admin`,
    `karakeep`, `navidrome`, `ntfy-admin`, `paperless`, `phoenix`, `quantum-admin`, `slskd`,
    `syncthing-home-forge`, `syncthing-oci-melb-1`, `tagr`, `termix-admin`, `vaultwarden-admin`,
    `webhook-admin`.
  - `repo.web.catalog.hosts` — empty (`catalogHostKeys=[]`): the catalog is service-keyed, not host-keyed.
  - `repo.web.currentHost.services` — **populated only on `la-admin-1`** (all 20 keys, with
    `publicUrl` values such as `kanidm-admin=https://id.shrublab.xyz`,
    `termix-admin=https://termix.shrublab.xyz`); **empty on `oci-melb-1` and `home-forge`**.
    `currentHost.hostName` is `null` on all three (the field is not exposed under that name).
  - `repo.web.policy.hosts` did not resolve as an evaluated path in this projection
    (`policyHostKeys=[]`); the host-key authority for evaluation purposes is the static
    `policy/web-services.nix` `hosts` block, which has the single `la-admin-1` key.
- **Identity-relevant hostname derivation today:** `services.tailscale.extraUpFlags` =
  `["--hostname=<networking.hostName>"]` on every host (`oci-melb-1`, `la-admin-1`, `home-forge`),
  with `authKeyFile=/run/secrets/tailscale.auth_key`, `useRoutingFeatures="none"`. Tailscale identity
  is therefore derived from `networking.hostName` at the aspect level, while the web policy restates
  the tailnet FQDN with a hardcoded tailnet domain (`tail0fe19b.ts.net`) — both are Stage 8 targets.

### 1.2.3 Host aspect selections (`modules/flake/registry.nix`, exact lines)

| Host | Record lines | Aspect selection lines |
|---|---|---|
| `oci-melb-1` | 66-114 | 73-101 (`provenance`, `oci-images`, `fleet-packages`, `web-policy`, `identity-client`, then `oci` 80 · `edge` 81 · `cockpit` 82 · `paperless` 83 · `postgres` 84 · `ai-gateway` 85 · `karakeep` 86 · `niks3-cache` 87 · `phoenix` 88; foundation `base` 90 · `shell` 91 · `networking` 92 · `tailscale` 93 · `notify` 94; operational `state-backups` 98 · `cache-publisher` 99 · `builder-access` 100 · `observability-agent` 101; host import 102) |
| `la-admin-1` | 116-154 | 120-151 (`sops-nix`, `provenance`, `oci-images`, `fleet-packages`, `web-policy`, `identity-client`; `edge` 128 · `cockpit` 129 · `push-server` 130 · `identity-provider` 131 · `vaultwarden` 132 · `termix` 133 · `gatus` 134 · `beszel` 135 · `homepage` 136 · `webhook` 137; foundation `base` 139 · `shell` 140 · `networking` 141 · `tailscale` 142 · `notify` 143; operational `state-backups` 147 · `cache-publisher` 148 · `builder-access` 149 · `observability-agent` 150; host import 151) |
| `home-forge` | 156-191 | 162-188 (`disko`, `sops-nix`, `provenance`, `oci-images`, `fleet-packages`, `web-policy`; `dj` 169 · `music` 170 · `omniroute` 174; foundation `base` 176 · `shell` 177 · `networking` 178 · `tailscale` 179 · `notify` 180; operational `state-backups` 184 · `cache-publisher` 185 · `builder-access` 186 · `observability-agent` 187; host import 188) |

Host system pins: `oci-melb-1 = aarch64-linux` (line 67), `la-admin-1 = x86_64-linux` (118),
`home-forge = x86_64-linux` (160). Only `oci-melb-1` carries `bootstrap` metadata (107-113).

### 1.2.4 Per-host structured observables

| Observable | oci-melb-1 | la-admin-1 | home-forge |
|---|---|---|---|
| `networking.hostName` | `oci-melb-1` | `la-admin-1` | `home-forge` |
| `networking.domain` | `null` | `null` | `null` |
| `services.tailscale.enable` | `true` | `true` | `true` |
| `services.tailscale.extraUpFlags` | `["--hostname=oci-melb-1"]` | `["--hostname=la-admin-1"]` | `["--hostname=home-forge"]` |
| `services.tailscale.authKeyFile` | `/run/secrets/tailscale.auth_key` | `/run/secrets/tailscale.auth_key` | `/run/secrets/tailscale.auth_key` |
| `services.niks3-auto-upload.enable` | `true` | `true` | `true` |
| `services.niks3-auto-upload.serverUrl` | `http://127.0.0.1:5751` (loopback optimization) | `http://oci-melb-1:5751` | `http://oci-melb-1:5751` |
| `services.niks3-auto-upload.authTokenFile` | `/run/secrets/niks3.api_token` | `/run/secrets/niks3.api_token` | `/run/secrets/niks3.api_token` |
| `services.niks3-post-deploy.enable` | `true` | `true` | `true` |
| `services.state-backups.enable` / `.bucket` | `true` / `shrublab-backup-oci-melb-1` | `true` / `shrublab-backup-la-admin-1` | `true` / `shrublab-backup-home-forge` |
| `applications.music.audiomuse.postgresHost` (aspect option) | `null` | `null` | **`oci-melb-1`** |
| `services.audiomuse.postgresHost` (leaf) | `null` | `null` | **`oci-melb-1`** / port `5432` |
| `fleet.foundation` keys | `["bootLoader","buildTmpfsSize"]` | same | same |
| `fleet.networking` keys | `["bridge","dns","uplink"]` | same | same |
| `config.deployment` root | **absent** | **absent** | **absent** |

Host source inventories (`modules/hosts/<host>/`):

- `oci-melb-1`: `default.nix`, `facter.json`, `disko-single-disk-split.nix`, `cockpit-auth.nix` (4 files)
- `la-admin-1`: `default.nix`, `facter.json`, `_admin-runtime.nix`, `cockpit-auth.nix` (4 files — no disko file; host is reimaged manually)
- `home-forge`: `default.nix`, `facter.json`, `disko-two-disk.nix` (3 files)

### 1.2.5 Registry internal shape, fleet facts, discovery boundary

- `registry.nix` declares a typed `hostRecord` submodule (lines 24-55) with `system` (str, explicit
  for mixed-arch materialization), `module` (`deferredModule` — host composition), `bootstrap`
  (`nullOr (attrsOf str)`, reimage-only), and a read-only `configuration` (`types.raw`) materialized
  at line 48-51 via `inputs.nixpkgs.lib.nixosSystem { system = config.system; modules = [ config.module ]; }`.
- Option: `nixos.configurations` = `types.lazyAttrsOf hostRecord` (lines 58-62). Concrete host names
  appear **only** in `config.nixos.configurations.<host>` (lines 66, 116, 156) — the exact sites task
  2.3 must genericize.
- Materialization: `flake.nixosConfigurations = mapAttrs (_: host: host.configuration) config.nixos.configurations`
  (line 194); `flake.bootstrap.nodes` (197-204) derives `hostName`/`flake` from the registry key and
  filters records with non-null `bootstrap`.
- Host facts live under `fleet.*` declared in host files: `fleet.foundation` (bootLoader,
  buildTmpfsSize — `modules/hosts/*/default.nix:27,34,43`) and `fleet.networking` (bridge, dns,
  uplink; consumed by `modules/flake/_aspects/networking.nix`).
- Discovery boundary: `flake.nix` builds `import-tree.filterNot` over `./modules` excluding
  `unconvertedNixosDirs = import ./modules/flake/_unconverted-nixos-dirs.nix`, which is currently
  exactly `[ "hosts" "services" ]` (25-line file documenting the Stage-by-Stage removals). Task 2.3's
  target end state is `[ "services" ]`.
- No `internal-service-contracts` option namespace exists yet (to be added by task 4.1).

### 1.2.6 Host derivation evaluation (3/3 PASS)

| Host | `…config.system.build.toplevel.drvPath` |
|---|---|
| `oci-melb-1` | `/nix/store/8x2r5n236r515m2kjp8l506yaajbl878-nixos-system-oci-melb-1-26.11.20260813.0e251e2.drv` |
| `la-admin-1` | `/nix/store/1m6p63cz9x77i14bz211ndc51x1lqsgj-nixos-system-la-admin-1-26.11.20260813.0e251e2.drv` |
| `home-forge` | `/nix/store/r7r67q1bc4irpfbxqwj59cksybh9r4lp-nixos-system-home-forge-26.11.20260813.0e251e2.drv` |

All three host config projections also evaluated `rc=0`. These store hashes are the pre-change
reference for Stage 8's equivalence gates (task 5.3's LA/home-forge closure comparison).

### 1.2.7 Migration checklist — concrete host-name literal sites to genericize

Counts are occurrences of `oci-melb-1`/`la-admin-1`/`home-forge` in each file.

**Authority sites (must become canonical-ID references):**

| Site | Count | Role |
|---|---|---|
| `modules/flake/registry.nix` | 6 | record keys + comments — tasks 2.2/2.3 |
| `lib/deploy/hosts.nix` | 9 | `edgeHost`, `deployOrder`, node keys + `hostName` — task 3.1 |
| `policy/web-services.nix` | 10 | `hosts.la-admin-1` key + `oci`/`homeForge` FQDN literals — task 3.2 |
| `lib/policy.nix` | 0 | generic `hostName` accessor + unknown-host throw — no literal, keep as reference authority |

**Consumer literals (task 4.2 / identity):**

- `modules/flake/_backups/niks3-upload-client.nix` (3) — `serverUrl = http://oci-melb-1:5751`
- `modules/flake/music.nix` (4) and `modules/services/music/audiomuse.nix` (1) — postgres host contract
- `modules/hosts/home-forge/default.nix` (6) — includes `audiomuse.postgresHost = "oci-melb-1"` (line 117)
- `modules/flake/identity-provider.nix` (6), `modules/services/ntfy.nix` (1),
  `modules/services/postgres-shared.nix` (2), `modules/services/tailscale.nix` (1)
- Host files: `modules/hosts/oci-melb-1/default.nix` (8), `modules/hosts/oci-melb-1/cockpit-auth.nix` (1),
  `modules/hosts/la-admin-1/default.nix` (7), `modules/hosts/la-admin-1/_admin-runtime.nix` (1)
- Other aspects carrying host names in comments/defaults: `ai-gateway`, `_aspects/base`,
  `beszel`, `cockpit`, `gatus`, `homepage`, `karakeep`, `niks3-cache`, `oci`, `omniroute`,
  `packages`, `paperless`, `phoenix`, `postgres`, `push-server`, `termix`, `vaultwarden`, `webhook` (1 each),
  `modules/services/admin/homepage/data.nix` (5), `modules/services/music/beets/default.nix` (1)

**Test + tooling surfaces (must stay green through the refactor):**

- `tests/check-dendritic-scaffold-contract.sh` (123), `tests/check-identity-contract-directionality.sh` (35),
  `tests/fixtures/secret-scope.nix` (25), `tests/phase-la-admin-contract.sh` (14),
  `tests/phase-02-03-host-contract.sh` (10), `tests/check-secret-scope.sh` (6),
  `tests/check-ssh-host-fingerprint.sh` (4), `tests/phase-04-service-flow-contract.sh` (4),
  `tests/check-secret-scope-extra-reader.sh` (3), `tests/kanidm-restore-contract.sh` (2)
- Single-occurrence tests: `check-backup-surface-contract.sh`, `check-host-age-anchor.sh`,
  `check-shell-account-contract.sh`, `check-web-service-catalog.sh`, `check-web-services-policy.sh`,
  `phase-03-*` (3), `phase-04.1/04.2/04-syncthing` (3)
- Tooling: `justfile` (5), `.just/ops.just` (3), `.just/checks.just` (1)

---

## Validation

- Host derivations: **3/3 PASS** (store paths above); host projection evals 3/3 `rc=0`.
- Flake outputs: `nixosConfigurations` 3 keys, `bootstrap.nodes` 1 key, deploy nodes 3 — captured.
- `git diff --check` scoped to the two touched files: clean.
- Not run (out of scope for 1.1/1.2): `treefmt`, `just checks all`, `nix flake check`, any build, any
  deploy, JJ/bookmark mutation.

## Residual risks / operator decisions

1. **Working copy is not the clean Stage 8 baseline commit.** `@` = `npmrwnkn` (user's USB change)
   with 25 dirty entries, and the brief's expected `mxknyqsp` is an un-checked-out empty change.
   Before task 2.x edits begin, the operator should either start Stage 8 as a fresh child after the
   dirty set is committed/isolated, or explicitly accept working from the dirty tree.
2. **Unrelated music/navidrome edits** (`modules/flake/music.nix`, `modules/services/music/navidrome.nix`,
   `modules/services/music/storage.nix`) sit in the tree this baseline evaluated. They are not
   deployment metadata, but Stage 8's final equivalence gates will compare against a moving target
   if they land mid-change.
3. **`split-state-backups-cache-publication` is unarchived.** Archive it to make its delta specs
   canonical before Stage 8's `sovereign-binary-cache`/`postgres-shared-access` deltas archive into
   the same capabilities.
4. **`repo.web.policy.hosts` did not resolve** as an evaluated path in the projection
   (`policyHostKeys=[]`), and `repo.web.currentHost.hostName` is `null` on all hosts. The web-host
   authority for task 3.2 is the static `policy/web-services.nix` `hosts` block (single `la-admin-1`
   key) plus `lib/policy.nix:5`'s `Unknown host` throw; task 3.2 should confirm the evaluated path
   before adding validation.
5. **`config.deployment` is absent** from host configurations; deploy metadata is flake-level only.
6. `fleet.foundation`/`fleet.networking` are the only current `fleet.*` namespaces — the canonical
   host-record schema (task 2.1) must not collide with them.
