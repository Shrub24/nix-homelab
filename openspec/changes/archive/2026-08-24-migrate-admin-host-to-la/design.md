## Context

`do-admin-1` is the public Caddy edge, Kanidm/OIDC provider, and host for the stateful admin surface. `oci-melb-1` depends on it for public ingress, Kanidm login, ntfy delivery, and Beszel monitoring. DigitalOcean credits will expire, while a 2 vCPU / 4 GB x86_64 LA VPS at `216.75.75.168` already runs NixOS and is reachable with password-based sudo.

The existing DigitalOcean host must remain live until LA has passed private validation and the Cloudflare origin cutover. This prevents an identity outage from becoming an unrecoverable fleet outage.

## Goals / Non-Goals

**Goals:**

- MIG-1: Replace `do-admin-1` with `la-admin-1` as the active x86_64 admin, Kanidm, and edge host while preserving private-origin exposure modes and all public URLs except the requested local-admin Cockpit path change.
- MIG-2: Adopt the existing LA NixOS installation safely from observed hardware and network facts, with key and provider-console recovery verified before password SSH is disabled.
- MIG-3: Preserve authoritative Kanidm, Vaultwarden, Termix, and Beszel state and ntfy auth (declarative SOPS auth-users/auth-tokens recreate `auth.db`); permit Quantum to start empty because its current payload is not authoritative.
- MIG-4: Preserve a rollback path through the still-running DO host until the LA host has passed post-cutover backup and recovery checks.
- MIG-5: Preserve least-privilege SOPS reader sets and introduce a distinct LA backup repository.

**Non-Goals:**

- Moving edge ingress to Australia, adding multi-edge routing, or hosting Kanidm outside LA.
- Assigning workloads to the future US-East host.
- Repartitioning, reimaging, encrypting, or otherwise mutating the LA VPS disk during adoption.
- Rotating identity, OIDC, Vaultwarden, Cloudflare, SMTP, or service credentials during the migration.
- Preserving Quantum files or starting Open WebUI before the host transition is complete.

## Decisions

### MIG-1: Use `la-admin-1` as the permanent host identity

**Chosen:** The replacement host is named `la-admin-1` in the OS, Tailscale, flake, deploy metadata, policy, secrets, and operations tooling.

**Why:** `modules/services/tailscale.nix` derives the stable Tailscale node hostname from `networking.hostName`, while the tagged auth key assigns the established tailnet roles (`tag:homelab` and, for the admin host, `tag:ssh-clients`). A second live `do-admin-1` would collide with the rollback host. A permanent name avoids an untested temporary override and a second rename without inventing host-scoped authorization tags.

**Alternatives considered:** Reusing `do-admin-1` delays the policy rename but prevents safe parallel tailnet validation. A temporary staging hostname adds a second cutover and more secret/deploy complexity.

### MIG-2: Adopt the live LA system non-destructively

**Chosen:** Capture a `nixos-facter` report on the LA guest and commit it at `hosts/la-admin-1/facter.json`; `hardware.facter.reportPath = ./facter.json` consumes it directly as the canonical source for hardware, drivers, virtualisation, and DHCP. The only hand-maintained storage facts are the existing root and ESP by-UUID mounts because facter does not report filesystems. The new host supplements that report only with observed `/srv/data`, boot, and provider-console facts, preserves the existing UEFI `systemd-boot` installation, and does not import DigitalOcean provider/network/disko configuration.

**Why:** The LA guest is KVM, UEFI, DHCP on `ens18`, and uses one ext4 root disk; it boots through `systemd-boot` on the existing ESP. A per-host report captures hardware-dependent modules without copying a generated configuration polluted by transient mounts. Guessing DHCP, static configuration, or a GRUB conversion risks losing the only active management session. `disko` and `nixos-anywhere` are installation tools, not adoption tools.

**Alternatives considered:** Reusing `hosts/do-admin-1/networking.nix` would pin the wrong addresses and interfaces. Reimaging would increase downtime and discard the provider's already-working NixOS installation.

### MIG-2a: Bootstrap the first LA generation from the repository, then use deploy-rs

**Chosen:** The existing password-sudo account applies the first source-controlled LA generation with `nixos-rebuild boot --target-host` and `--use-remote-sudo`. The operator reboots through the provider console. Subsequent deployments use deploy-rs as `dev` after the NixOS generation has declared its SSH keys and recovery configuration.

**Why:** The current host predates fleet configuration, so deploy-rs cannot safely assume its `dev` user exists. `boot` avoids applying a network-owner configuration to the live SSH session; provider-console reboot verifies the selected boot and break-glass path.

**Alternatives considered:** Manually creating and maintaining a temporary `dev` user duplicates fleet state. A live `switch` risks the prior network-owner failure mode. Reimaging is destructive and unnecessary.

### MIG-2b: Separate managed operator and minimal recovery shells

**Chosen:** `dev` explicitly uses the managed Zsh operator shell. Its startup file is provisioned after account-home creation, so the first post-boot login is ready without interactive setup. `root` and the console-only `rescue` account use `bashInteractive`; `root` retains the shared recovery SSH keys but does not inherit Zsh prompt, plugin, or alias configuration.

**Why:** A `users.defaultUserShell` setting made both `dev` and `root` inherit the full Zsh environment, while the `dev` dotfile activation ran before `/home/dev` existed on the initial boot. The resulting first login prompted for interactive Zsh setup and made root look like an operator account. Explicit per-user shells and an ordered startup-file provision preserve a predictable operator experience and a boring recovery path.

**Alternatives considered:** Fish would introduce a second shell ecosystem without solving the timing or recovery-account problem. Managing root dotfiles or deleting existing root state is unnecessary: a Bash login shell and operator-only Zsh configuration establish the desired boundary declaratively.

### MIG-2c: Scope the LA Tailscale SSH key-exchange workaround to deployment metadata

**Chosen:** During adoption, LA's physical deployment metadata supplied `-o KexAlgorithms=curve25519-sha256` to deploy-rs and its post-deploy SSH hook, as an LA-only option that left enrollment, role tags, MagicDNS, NixOS firewall policy, and the provider-console recovery path unchanged. That override has since been removed: after the planned Tailscale update, a fresh default `mlkem768x25519-sha256` session to `la-admin-1` succeeded over the tailnet, so deployment tooling now uses default SSH algorithm negotiation with no host-specific `KexAlgorithms` override.

**Why:** LA is online with the same `tag:homelab` and `tag:ssh-clients` roles as DO; MagicDNS, direct Tailscale ping, and HTTP by both tailnet IP and DNS name work. Fresh default SSH sessions from the same client complete ML-KEM against DO and OCI but stall waiting for LA's KEX reply. A fresh Curve25519 session against LA reaches the pinned host key and authenticates successfully. Restarting `tailscaled` did not change the failure. Tailscale's own discovery log reports a 1360-byte wire MTU for the workstation peer, exactly sufficient for its 1280-byte TUN after 80 bytes of encapsulation, so the earlier large-ICMP result does not justify an MTU override or provider ticket.

**Alternatives considered:** Re-enrollment would rotate healthy node identity without changing the proven KEX boundary. A fleet-wide algorithm override would weaken defaults on unaffected hosts. A Tailscale MTU override is unsupported by the peer-specific evidence. Waiting for a package update would leave the non-mutating deploy-rs preflight blocked.

### MIG-3: Keep the current role colocation for this transition

**Chosen:** LA runs the same edge, identity, and admin roles as DO. Routes remain Cloudflare-to-Caddy with private Tailscale origins; only the local-admin Cockpit path changes from its DigitalOcean-derived path to `/la-admin-1`.

**Why:** The current policy has edge-local admin upstreams and OCI Tailscale origins. Splitting edge now would require refactoring those upstream contracts while also moving identity and stateful services.

**Alternatives considered:** An immediate Australian edge adds a proxy hop for LA-hosted services and is not necessary to retire DO. Running edge on `oci-melb-1` couples public ingress to an existing workload host.

### MIG-3a: Use service policy, not host roles, for cross-host consumers

**Chosen:** `lib/policy.nix` exposes a duplicate-key-checked catalog of resolved services. `modules/shared/web-policy.nix` exposes it as `config.repo.web.catalog`. Cross-host consumers read stable service IDs such as `kanidm-admin`, `paperless`, and `karakeep` for public URL, access, and health metadata.

**Why:** The three current OCI consumers need a service contract, not the host that happens to supply it. A general role-to-host registry recreates host indirection and becomes misleading if identity and edge later split.

**Alternatives considered:** Keep `config.repo.web.hosts.<hostname>` requires each host replacement to edit consumers. A fleet-wide role registry moves the same coupling behind another name. A separate global URL constant would duplicate the canonical route policy.

### MIG-3b: Keep a small physical deployment boundary

**Chosen:** `lib/deploy/hosts.nix` owns `edgeHost` and `deployOrder` for scripts, tests, and deployment sequencing. GitHub Actions keeps explicit physical job names because it cannot evaluate the flake natively.

**Why:** Deployment target selection and serial order are inherently physical facts. Keeping them in the deploy metadata creates one intentional place to change on a future replacement.

**Alternatives considered:** Deriving deployment order from service policy conflates runtime routes with operations. General role metadata is unnecessary until a real multi-host role assignment needs it.

### MIG-4: Use staged restore followed by a short authoritative freeze

**Chosen:** Restore a recent DO snapshot to LA for private, read-only validation. During a planned maintenance window, quiesce source writers, create a final managed backup, restore final state on LA (ntfy auth recreated declaratively — see MIG-5), then change the Cloudflare origin endpoint.

**Why:** Kanidm, Vaultwarden, and ntfy must have one writer. This produces a bounded maintenance window and makes DNS rollback valid before new writes occur.

**Alternatives considered:** Running two writable instances creates split-brain state. A no-outage replication design is not justified by this one-time migration.

### MIG-5: Preserve state according to authority and backup coverage

**Chosen:** Kanidm 1.10.4 portable backups at `/var/lib/kanidm/backups/backup-*.json.gz` are its authoritative migration source; `/var/lib/kanidm/kanidm.db` is its live database, while the legacy `/srv/data/kanidm` path is not server state and is removed from the backup contract. LA must use the same Kanidm package version, restore the portable artifact while `kanidm.service` is stopped, verify it offline, then start with byte-identical domain, identity, provisioning, and OIDC inputs. Offline verification is a strict gate: it accepts a zero exit only with its clean-success marker and no error-bearing output. It otherwise fails closed before ownership repair or service start, except for the one source-proven v1.10.4 condition: exactly `RefintNotUpheld(319)` with no other verifier error, where read-only `db-scan` independently proves entry `319` is an `oauth2_session` in `RevokedAt` state whose `rs_uuid` is the missing `05e3c021-5b84-417e-8d4c-ed2f2d9c88b7` resource server. Any version mismatch, output-shape mismatch, second finding, or failed scan is fatal; the helper never writes, quarantines, or repairs the source or restored database to pass. Upstream evidence shows `RefintNotUpheld(<id>)` identifies the entry holding a dangling reference; entry 319 is live, and its empty `recycled_directmemberof - <cid> -` line is changestate residue after revive, not non-live evidence. Vaultwarden export plus raw state, Termix and Beszel state, and ntfy auth are migrated. ntfy is not copied: its auth users/tokens are declarative SOPS input and `auth.db` is recreated from them, so a stale LA `auth.db` is removed before the declarative reprovisioning (never merged); cache/history/attachments are accepted ephemeral state (no attachments exist today), and if attachments become authoritative later their real path is added to restic first. Quantum starts empty.

**Why:** The portable export is produced by Kanidm's built-in online backup and is already captured by restic. The verifier includes revoked OAuth session references that are retained for replication history and lacks a revoked-session exemption, so the source-proven condition is not database corruption or a live reference defect. The exact predicate preserves the verifier as a gate rather than broadly downgrading `RefintNotUpheld`; a fresh export copies the same retained session and cannot resolve it. Restoring a fresh target database or starting provisioning before restore risks account reset, OIDC drift, or automatic deletion of undeclared state. Provisioning readiness uses Kanidm's upstream loopback default, not the public Cloudflare route: target startup before cutover must not require an Origin Pull client certificate or public DNS to resolve to the target.

**Alternatives considered:** Directly copying ntfy state was considered and rejected: auth users/tokens are declarative SOPS input and `auth.db` is recreated from them, while cache/history/attachments are accepted ephemeral state (no attachments exist today). Copying Quantum payload adds cutover work without current value.

### MIG-6: Separate LA backup ownership from DO recovery evidence

**Chosen:** LA writes to a new `shrublab-backup-la-admin-1` R2 repository or bucket. The DO repository and a final DO snapshot remain retained until LA completes a verified backup and restore cycle. Database coverage is export-first: PostgreSQL, Kanidm, Vaultwarden, and Tagr create consistent recovery artifacts before restic snapshots them. Backup paths name real data directories rather than compatibility symlinks, and a canonical state-restore runbook plus a safe staging recipe define the recovery path without overwriting live state.

**Why:** Host-scoped repositories keep retention, ownership, and recovery provenance unambiguous. Logical database exports avoid treating crash-consistent live database directories as portable recovery artifacts, while staged restores keep routine verification non-destructive.

**Alternatives considered:** Reusing the DO repository is faster but mixes retired-host history with LA backups.

### MIG-7: Preserve secret values while changing readers and paths

**Chosen:** The operator creates LA encrypted host secrets from repository templates and re-encrypts moving feature scopes for the LA recipient. Existing sensitive values remain unchanged. The DO recipient is removed immediately from moved LA-only/admin/identity scopes and retained only on scopes the still-running rollback host actively reads.

**Why:** Stable values preserve Kanidm OIDC client registrations, Cloudflare Access, and service credentials. Explicit reader sets keep the secret blast radius aligned with active topology.

**Alternatives considered:** Credential rotation would make fault isolation harder during migration. Leaving old reader access after retirement violates least privilege.

### MIG-7a: Treat host, operator, and outbound SSH keys as separate identities

**Chosen:** The persistent LA SSH **host** ed25519 key is fingerprint-verified through the provider console and converted to `&la_admin_1_age`; sops-nix reads that existing host key rather than a separately managed age private key. Fleet operator login keys remain declared in `modules/core/users.nix`. LA receives a new `identity/ssh_private_key` secret for outbound `dev` SSH, and its public half is added once to that central trust set.

**Why:** The host key is the LA machine's decryption identity, operator keys authorize human access, and the outbound identity authorizes the LA `dev` user to reach fleet peers. Reusing the DO outbound identity leaves two live hosts sharing a principal.

### MIG-9: Use a defined runbook and a 24-hour live rollback window

**Chosen:** `docs/runbooks/host-initialization.md` is the canonical generic runbook. It distinguishes preinstalled-NixOS adoption from destructive `nixos-anywhere`/`disko` bootstrap, defines the host-key/age, SSH, secrets, Tailscale, recovery, and first-deployment SSOT boundaries, and contains no LA-specific values. `docs/runbooks/admin-host-migration.md` references it and records the LA-only transfer details. DO remains live for 24 hours after cutover and one verified LA backup; it is then snapshot-retained and destroyed.

**Why:** A generic runbook prevents the next host from recreating this discovery work, while the migration runbook keeps one-off transfer evidence separate. The 24-hour window balances real rollback with the expiring-credit constraint.

### MIG-8: Gate unrelated delivery work

**Chosen:** The active `open-webui` change is not deployed until this migration's cutover and backup gates pass.

**Why:** Both changes touch edge policy and secrets. Separating them makes cutover provenance and rollback clear.

## Risks / Trade-offs

- [LA networking differs from the assumed provider model] → Capture `ip`, route, interface, boot, and hardware facts before writing host networking; retain the provider console through first switch.
- [Incorrect fact report] → Run `nixos-facter` as root on the LA guest only, without `--swap` or `--ephemeral`; review and commit its single-host report rather than sharing or regenerating it on another node.
- [Bootloader replacement] → Explicitly override the base GRUB default for LA, preserve the current systemd-boot ESP, and use provider-console boot verification before declaring the host reachable.
- [First switch disables password SSH] → Install and test key-based SSH first; keep the original console session open until a second key-based session succeeds.
- [First-generation access loss] → Apply `boot`, not live `switch`; retain a provider-console session and verify declared `dev` key SSH plus console-only `rescue` login after reboot.
- [LA Tailscale SSH stalls during ML-KEM] → An updated Tailscale generation now passes a fresh default ML-KEM session, so the LA-only Curve25519 override was removed; if the stall regresses, restore the override in physical deployment metadata and re-verify.
- [First boot starts enabled services before state restore] → Before restoring or staging another reboot, explicitly stop LA's Kanidm, Vaultwarden, Termix/guacd, Quantum, Beszel hub, ntfy, and restic backup units; stop the restic-backup, recovery-reboot, and nh-clean timers and verify each is loaded, inactive, and has no next trigger; retain Tailscale. Keep those writers quiesced until restored state is validated. Do not rely on runtime masks: NixOS's generated unit links under `/etc/systemd/system` outrank `/run/systemd/system` masks.
- [Wrong host age recipient] → Compare the live host-key fingerprint from console with the scanned public key before updating `.sops.yaml`; never regenerate the verified host key.
- [`/build` tmpfs or bootloader mismatch] → Size or override the base-server build tmpfs and boot settings from observed 4 GB and boot-mode facts before first boot.
- [Kanidm/OIDC outage] → Restore and validate LA privately, preserve OIDC secret values, use a planned freeze, and keep DO live for origin rollback.
- [State divergence] → Treat DO as authoritative until the freeze; prohibit write testing on LA; do not roll DNS back after LA writes without choosing the authoritative dataset.
- [Kanidm false recovery coverage] → Back up the portable export path rather than the unused `/srv/data/kanidm`; use a source-controlled restore helper/mode to restore and verify while the target service is stopped.
- [Revoked OAuth session triggers a v1.10.4 false positive] → Accept it only through the hard-pinned entry, resource-server UUID, session-state, index, and output-shape predicate; never weaken unrelated verifier failures or mutate the database.
- [Catalog exposes edge-local origins] → Catalog consumers use only `publicUrl`, `access`, and health metadata; local origin fields remain for edge-local rendering only.
- [Duplicate service IDs] → Catalog construction fails evaluation if two policy owners declare the same route key.
- [Ntfy notification continuity] → Auth users/tokens are declarative SOPS input and `auth.db` is recreated from them; remove any stale LA `auth.db` before the declarative reprovisioning (never merge); cache/history/attachments are accepted ephemeral state (no attachments exist today).
- [Secret scope drift] → Change `.sops.yaml`, host-secret templates, and `tests/check-secret-scope.sh` together; operator re-encrypts ciphertext separately.
- [Unexpected 4 GB resource pressure] → Record DO memory/disk high-water marks before cutover and monitor LA for OOM events before retiring DO.
- [DigitalOcean billing deadline] → Take a final restic backup and DO snapshot before destroying the droplet; a powered-off droplet is not a cost-free fallback.

## Migration Plan

1. Preserve DO recovery evidence: managed restic run/status/log evidence, ntfy declarative-auth reprovisioning notes, resource measurements, and provider snapshot.
2. Capture and review the LA-only `nixos-facter` report, system facts, `/srv/data` capacity, provider-console recovery procedure, and verified SSH host-key fingerprint.
3. Implement and validate the policy service catalog, physical deployment boundary, host-neutral Cockpit route key, and the `la-admin-1` configuration without deploying it to DO.
4. Rename the local-admin Cockpit public path to `/la-admin-1` in the same policy update; update generated policy output and operator documentation.
5. Operator derives the LA recipient from the verified host key, creates LA secret ciphertext including a new outbound identity, creates a Tailscale auth key carrying `tag:homelab` and `tag:ssh-clients`, creates the LA R2 target, and makes Cloudflare runtime origin input available locally.
6. Apply the first LA generation with source-controlled `nixos-rebuild boot` via the existing password-sudo account; reboot through the provider console; then verify declared key SSH, Tailscale, and break-glass access before deploy-rs takes over.
7. Quiesce LA state writers and backup/reboot/GC timers, then restore a recent version-matched Kanidm portable export through the source-controlled stopped-service restore helper; only after restored state is safe to start, reboot into the staged generation and verify identity, OIDC, admin services, OCI dependencies, and public-route behavior without sending public traffic to LA. During this window, use deploy-rs dry activation only; a normal deploy-rs switch starts enabled services and follows the restore gate.
8. Freeze DO writers, create a final portable Kanidm backup, restore final LA state through the helper (ntfy auth recreated declaratively per the state-restore runbook), and verify the LA stack.
9. Render and apply the policy-driven OpenTofu origin update to `216.75.75.168`; run the cutover verification matrix.
10. Run and verify a LA backup. After the 24-hour soak window, snapshot and destroy DO, revoke its tailnet device, remove its SOPS recipient, and delete legacy configuration.

## Open Questions

- LA facts captured in tasks 1.1–1.2 are recorded in `docs/runbooks/admin-host-migration.md`; that runbook is the reference before the first deployment, and the implementation task must stop on any fact mismatch.
- The initial password-sudo account is `root`, recorded in the LA migration runbook. Stop the implementation if that fact no longer matches the host.
