# Baseline — `split-state-backups-cache-publication` (task 1.1)

## 1. Pinned revisions

- **Parent (`@-`):** JJ `vqylpuvw` / git `962da197` — "refactor: decouple identity and admin capabilities" (post-D-054, committed).
- **Child (`@`, this change applies on):** JJ `zwltwwun` / git `bea49e9e` — "(empty) planning: split state backups and cache publication aspects".
- Captured 2026-09-18 from the clean child working copy.

## 2. Per-host observables

Raw JSON: `/tmp/nix-homelab-split-evidence/{oci-melb-1,la-admin-1,home-forge}.json` (probe: `nix eval --apply` over `nixosConfigurations.<host>.config`; probe file kept at `/tmp/nix-homelab-split-evidence/probe.nix`).

### State-backup inventory (must stay equal through the split)

| observable | oci-melb-1 | la-admin-1 | home-forge |
|---|---|---|---|
| `services.state-backups.enable` | true | true | true |
| `backupName` | `state` | `state` | `state` |
| `bucket` | `shrublab-backup-oci-melb-1` | `shrublab-backup-la-admin-1` | `shrublab-backup-home-forge` |
| `secretFile` | `…/secrets/hosts/<host>/system.yaml` | same | same |
| `stagingRoot` | `/srv/data/state-backups` | same | same |
| host-core paths | `[]` | `[]` | `["/etc/ssh"]` |
| `services.restic.backups."state".repository` | `s3:https://bef816e6776e8f13f…` (identical prefix all hosts) | same | same |
| timer `restic-backups-state.wantedBy` | `["timers.target"]` | same | same |
| unit `onFailure` | `["svc-monitor@restic-backups-state.service"]` | same | same |
| restic password sops | key `backup/restic_password`, path `/run/secrets/state-backups.restic_password`, file `system.yaml` | same | same |

### Cache-publication inventory (must stay equal through the split)

| observable | oci-melb-1 | la-admin-1 | home-forge |
|---|---|---|---|
| `services.niks3-post-deploy.enable` | true | true | true |
| `excludePublicKeys` | 3 keys (cache.nixos.org, nix-community.cachix.org, cache.numtide.com) | same | same |
| `services.niks3-auto-upload.enable` | true | true | true |
| `serverUrl` | `http://127.0.0.1:5751` (loopback) | `http://oci-melb-1:5751` | `http://oci-melb-1:5751` |
| `authTokenFile` | `/run/secrets/niks3.api_token` | same | same |
| token sops | key `niks3/api_token`, path `/run/secrets/niks3.api_token`, mode `0400`, owner `niks3` | owner `null` (default) | owner `null` |
| `services.notification-daemon.monitor.enable` | true | true | true |
| `repo.packages.nix-path-filter` available | true | true | true |
| activation script `system.activationScripts.niks3-post-deploy` | string: `mkdir -p /run/niks3-post-deploy` → `readlink -f "$systemConfig" > /run/niks3-post-deploy/target` → conditional `systemctl start --no-block niks3-post-deploy.service \|\| true` | same (store-path hash differs) | same |

### Backup assertions (in `modules/flake/backups.nix`)

- Bucket-name validity: line 22 `bucketNameValid = builtins.match "^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$" bucketName != null;` wired as an assertion at line 55.
- Monitor assertion: line 65 message `"backups aspect: services.notification-daemon.monitor.enable must be true (select the notify aspect) so restic-backups-state failures route through svc-monitor."` (message text will be re-owned in the split; both assertions must survive).
- Restic unit failure hook: `modules/services/state-backups.nix:368-369` sets `systemd.services."restic-backups-${cfg.backupName}".onFailure = lib.mkBefore [ "svc-monitor@restic-backups-${cfg.backupName}.service" ]`.

## 3. Current composition (to be split)

- `modules/flake/registry.nix` selects `aspects.backups` at **lines 96 (oci-melb-1), 142 (la-admin-1), 176 (home-forge)** — each inside the "Operational aspects" block beside `aspects.builder-access` / `aspects.observability-agent`.
- `modules/flake/backups.nix` import list: `inputs.niks3.nixosModules.niks3-auto-upload`, `../services/state-backups.nix`, `./_backups/niks3-upload-client.nix`, `./_backups/niks3-post-deploy.nix`. It owns: host secret gate (`../../secrets/hosts + "/${hostName}/system.yaml"` → `hasHostSecrets`), bucket derivation + S3 validity assertion, `services.state-backups` mkIf-gated defaults, `services.niks3-post-deploy` mkIf-gated defaults with `withSystem` `nix-path-filter` injection, and the monitor assertion.
- Registry imports the niks3 **server** module separately (`modules/flake/registry.nix:72` `inputs.niks3.nixosModules.niks3`) — out of scope, untouched.

## 4. Two-inventory explicitness check

- **State-backup inventory:** non-empty on all three hosts — restic backup `state` (unit `restic-backups-state` + timer, `timers.target`), S3 repository, staging root, host-core path sets enumerated above, password secret registration.
- **Cache-publication inventory:** non-empty on all three hosts — `niks3-auto-upload` unit with server URL/auth token, `niks3-post-deploy` unit + activation script + 3 exclude keys, `niks3_api_token` secret registration, post-deploy closure filter availability.
- Both inventories are explicit and enumerable; the combined `backups` aspect is the only composition owner today.

## 5. Scope guards verified this run

- `git diff --name-only -- secrets/ .sops.yaml flake.lock modules/services/niks3.nix` → **0 files** (ciphertext, sops rules, lockfile, niks3 server module untouched).
- Registry niks3 server import (`inputs.niks3.nixosModules.niks3`, line 72) present and untouched.
- `nix.settings.post-build-hook = lib.mkForce "";` present verbatim at `modules/flake/_backups/niks3-post-deploy.nix:42` (compatibility suppression — must survive the split).
- No code files modified this run; only `baseline.md` + task 1.1 checkbox added.

## 6. Eval-failure notes (diagnostic trail)

- First probe attempt failed: `undefined variable 'activationScript'` (bare `inherit` inside `builtins.toJSON { … }` — string-apply parsing issue, test-harness class).
- `system.activationScripts.niks3-post-deploy` is a **string**, not an attrset (`.text` projection fails: "is not an attribute set") — corrected with `toString (… or "")`.
- Final probe (`--raw --apply` returning `builtins.toJSON …`) succeeded on all three hosts, rc=0.
