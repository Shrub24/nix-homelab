## 1. Establish operator evidence and recovery prerequisites

- [x] 1.1 Capture LA hardware, boot, disk, network, storage-capacity, and initial-login facts without modifying the host.
  - refs: `nixos-facter`, `hosts/do-admin-1/hardware-configuration.nix`, `docs/context-history.md`
  - criteria: Generate a LA-only `nixos-facter` report without `--swap` or `--ephemeral`; record `nixos-version`, `uname -m`, `lsblk -f`, `findmnt`, `df -h`, `ip -br addr`, `ip route`, EFI/boot mode, `/srv/data` availability, the initial sudo account, and the provider-console recovery procedure for `216.75.75.168`.
  - verify: Operator supplied the reviewed LA `facter.json`, runtime-fact output, root bootstrap account, persistent-volume confirmation, and provider-console capability; task 2.7 records them in the runbook.

- [x] 1.2 Verify the persistent LA SSH host key and provider-console recovery before the first fleet boot.
  - refs: `modules/core/base.nix`, `modules/core/users.nix`, `modules/shared/host-recovery.nix`
  - criteria: The console-reported fingerprint matches `/etc/ssh/ssh_host_ed25519_key.pub`; the root filesystem preserves that host key; the provider console can perform and observe a reboot.
  - verify: Operator supplied the persistent-volume confirmation, provider-console capability, and fingerprint `SHA256:g71ri368dh+EkeJgXrHmMsrxlkwHI2T9G8rFD+G6fWw`; task 2.7 records the procedure before recipient derivation.

- [x] 1.3 Preserve DigitalOcean recovery evidence and measure the source host.
  - refs: `.just/backups.just`, `modules/services/state-backups.nix`, `docs/architecture.md`
  - criteria: Record a successful DO restic run/status/log sequence, Kanidm backup artifact presence, Vaultwarden export presence, memory/disk high-water data, and a provider snapshot plan; prepare the declarative ntfy auth reprovisioning procedure. The status recipe SHALL treat a completed successful oneshot backup as healthy rather than failing solely because it is inactive.
  - verify: Fresh snapshot `ba905ecb` completed at `2026-08-07 07:49 UTC`; its Restic check reported no errors, Kanidm backup and Vaultwarden export were present, and ntfy state was identified at `/srv/data/ntfy`; staged restore evidence is captured in task 4.3.

- [x] 1.4 Prove and document the version-specific Kanidm restore sequence before the migration window.
  - refs: `modules/services/admin/kanidm.nix`, `modules/services/admin/kanidm-provision.nix`, `docs/runbooks/admin-host-migration.md`
  - criteria: Kanidm 1.10.4 portable artifacts at `/var/lib/kanidm/backups/backup-*.json.gz` are the authoritative restore input; the stopped target restores and verifies that artifact before first service start; matching domain, package version, identity, provisioning, and OIDC inputs are verified before post-start provisioning.
  - delegate: CodeScout
  - verify: Source and upstream review confirmed `kanidmd database restore`/`verify` require the service stopped, the DO artifact set is present, and `/srv/data/kanidm` is not the server database; task 2.5 implements the source-controlled restore helper and task 2.7 records the procedure.

## 2. Build the replacement host configuration

- [x] 2.1 Add a thin non-destructive `la-admin-1` host assembly from captured LA facts.
  - refs: `hosts/do-admin-1/default.nix`, `hosts/la-admin-1/facter.json`, `modules/profiles/base-server.nix`, `modules/services/tailscale.nix`
  - criteria: The new x86_64 host composes the existing admin, edge, identity, backup, recovery, notification, and cache-consumer roles; it sets `hardware.facter.reportPath = ./facter.json` directly and has no hand-written driver, virtualisation, or network-interface configuration. It has no DigitalOcean provider import, static DO interface configuration, `nixos-anywhere`, destructive disko activation, or inherited GRUB-removable-media bootloader. Its only explicit storage facts are the observed root and ESP by-UUID mounts that facter cannot report; `/srv/data`, `/build`, and existing UEFI systemd-boot behavior derive from captured LA facts.
  - delegate: CoderAgent
  - verify: Targeted host-module evaluation and `nixfmt --check` passed; full toplevel evaluation is deferred to task 3.1 because task 2.2 must register the flake output and tasks 2.3–2.4 must establish the LA policy host.

- [x] 2.2 Separate physical deployment topology from deploy node definitions, then register `la-admin-1` while retaining `do-admin-1` as an undeployed rollback host.
  - refs: `flake.nix`, `lib/deploy/hosts.nix`, `justfile`, `.just/`, `.github/workflows/deploy.yml`, `.github/workflows/deploy-host.yml`
  - criteria: A `nodes` map remains the only input to deploy-rs node generation; `edgeHost` and `deployOrder` live alongside it without being interpreted as NixOS nodes; LA uses its public bootstrap address and Tailscale identity; regular deployment and CI select LA before OCI.
  - delegate: CoderAgent
  - verify: `deployHosts.edgeHost`, `deployOrder`, node isolation, OCI/DO deploy profiles, workflow YAML, just parsing, and formatting passed. The LA profile evaluation is deferred to task 3.1 because task 2.4 must first add the LA web-policy host.

- [x] 2.3 Add the canonical policy service catalog and the minimal physical deployment boundary.
  - refs: `lib/policy.nix`, `modules/shared/web-policy.nix`, `lib/deploy/hosts.nix`, `hosts/oci-melb-1/default.nix`
  - criteria: Cross-host consumers resolve stable service IDs through `config.repo.web.catalog`; duplicate service IDs fail evaluation; only `edgeHost` and `deployOrder` remain as central physical deployment facts.
  - delegate: CoderAgent
  - verify: `./tests/check-web-service-catalog.sh` and `nix eval .#deployHosts.edgeHost` pass, including duplicate-key rejection and the exact exported physical-boundary shape.

- [x] 2.4 Move the canonical active edge/admin policy identity from `do-admin-1` to `la-admin-1`, rename the local-admin Cockpit route key, and deliberately change its public path to `/la-admin-1`.
  - refs: `policy/web-services.nix`, `lib/policy.nix`, `generated/policy/web-services.json`, `modules/applications/edge-ingress.nix`, `modules/services/edge-proxy-ingress.nix`
  - criteria: Every currently declared public route has one LA-owned policy definition; OCI routes retain private Tailscale origins; Cloudflare Access and AOP exceptions are preserved; the local-admin Cockpit policy key is host-neutral and its public path is `/la-admin-1`.
  - delegate: CoderAgent
  - verify: `./tests/check-web-services-policy.sh la-admin-1`, `./tests/check-web-service-catalog.sh`, and `nix eval .#deployHosts.edgeHost` pass; the generated policy output matches source and the inactive DO rollback profile remains evaluable.

- [x] 2.5 Update host-keyed admin wiring, OIDC consumer references, ntfy transition access, and host contract tests for `la-admin-1`.
  - refs: `modules/applications/admin/default.nix`, `modules/services/admin/`, `modules/services/ntfy.nix`, `hosts/oci-melb-1/default.nix`, `tests/phase-do-admin-contract.sh`
  - criteria: LA supplies Kanidm/OIDC and edge services; OCI consumes canonical policy service metadata rather than admin-host names; both old and new admin tags may publish to ntfy during transition; Quantum starts empty. Kanidm state backup captures only the authoritative portable backup export rather than unused `/srv/data/kanidm`, and a source-controlled restore helper/mode restores and verifies it while `kanidm.service` is stopped before first authority start.
  - delegate: CoderAgent
  - verify: Kanidm restore contract, LA/DO/OCI host contracts, secret-scope, web-policy, and catalog checks pass. `just checks all` is blocked only by absent operator-owned LA ciphertext, which task 2.6 prepares but does not create.

- [x] 2.6 Add complete LA secret templates and enforce explicit non-secret recipient/scope policy without decrypting or editing ciphertext.
  - refs: `secrets/.templates/`, `.sops.yaml`, `tests/check-secret-scope.sh`, `secrets/justfile`, `.just/host-age.just`
  - criteria: Templates include the Cockpit service-password hash and Beszel token as well as host system and OIDC inputs; the scope fixture/check covers every moving common, identity, ntfy, notification, OpenTofu, and host secret path; `.sops.yaml` documents only necessary LA reader access and transition-reader removal; no encrypted payload is created, decrypted, or changed by the agent.
  - delegate: CoderAgent
  - verify: `./tests/check-secret-scope.sh` passes all 18 declared scopes; focused security review confirmed LA-only scope narrowing, retained DO rollback readers, and removal of two unnecessary OCI readers. No ciphertext was touched.

- [x] 2.7 Create the canonical host-initialization runbook and update architecture, decisions, plan, and the LA migration runbook.
  - refs: `docs/architecture.md`, `docs/decisions.md`, `docs/plan.md`, `openspec/changes/open-webui/`
  - criteria: `docs/runbooks/host-initialization.md` covers both preinstalled-NixOS adoption and destructive reimage selection; it defines fact capture, verified SSH-host-key-to-age derivation, operator-key and outbound-key ownership, SOPS/Tailscale/recovery handoff, source-controlled first boot, and deploy-rs steady state. The LA runbook references it and contains only LA transfer facts. Documentation distinguishes LA adoption from later AU edge and US-East workload work, defines the catalog-versus-physical-boundary rule, source-freeze/rollback steps, and user-owned encrypted-secret actions.
  - delegate: DocWriter
  - verify: `git diff --check` passes; documentation review confirmed consistent adoption/reimage guidance, root bootstrap account, scoped recipient retention, and LA-active/DO-rollback topology.

## 3. Validate configuration and complete user-owned bootstrap

- [x] 3.1 Run repository formatting, policy-catalog, secret-scope, and flake evaluation checks for the replacement topology.
  - refs: `treefmt.toml`, `.just/checks.just`, `flake.nix`
  - criteria: The checked topology contains both the running DO rollback host and the new LA target without policy/catalog or secret-scope ambiguity; deployment topology metadata cannot be mistaken for a node.
  - delegate: BuildAgent
  - verify: `just fmt-check`, host/policy/catalog/secret-scope contracts, and DO/OCI deploy-profile evaluation pass. `just checks all` reaches the expected operator-owned blocker: the absent `secrets/hosts/la-admin-1/system.yaml`; rerun it after task 3.3 and before task 4.1.

- [x] 3.2 Review the migration diff for destructive disk, networking, secret-scope, deployment-target, and rollback defects.
  - refs: `proposal.md`, `design.md`, `tasks.md`
  - criteria: The diff does not deploy LA configuration to DO, does not assume DHCP/static configuration without evidence, and does not expose secrets or widen unrelated recipient access.
  - delegate: CodeReviewer
  - verify: Follow-up review reports no unresolved high- or medium-severity finding after task 3.2a remediation.

- [x] 3.2a Close the migration safety findings before operator bootstrap.
  - refs: `.github/workflows/deploy-host.yml`, `lib/deploy/hosts.nix`, `tests/check-secret-scope.sh`, `.just/checks.just`, `tests/phase-la-admin-contract.sh`
  - criteria: CI derives a `known_hosts` entry only after the discovered LA host key matches the source-controlled, console-verified fingerprint; it never disables SSH host checking. Unexpected SOPS readers fail the scope check. The standard checks recipe runs LA/DO rollback and Kanidm restore contracts, including LA adoption bootloader/non-destructive-input assertions.
  - delegate: CoderAgent
  - verify: SSH fingerprint, negative secret-reader, LA/DO/Kanidm phase contracts, standard checks recipe, and exact CI checks invocation pass; final review reports no unresolved high- or medium-severity finding.

- [x] 3.2b Render the declared ntfy transition publisher ACL before creating the LA notification token.
  - refs: `modules/services/ntfy.nix`, `hosts/la-admin-1/default.nix`, `tests/phase-la-admin-contract.sh`
  - criteria: Auth-enabled ntfy configuration renders `services.ntfy.auth.access` to the generated server configuration; the LA transition permits only the explicit OCI, LA, and DO write-only publishers while the default remains deny-all.
  - delegate: CoderAgent
  - verify: Ciphertext-safe generated-config assertion proves deny-all plus exactly OCI/LA/DO write-only transition publishers; focused contract and standard checks pass.

- [x] 3.2c Align ntfy transition ACL subjects with their token-service users.
  - refs: `hosts/la-admin-1/default.nix`, `secrets/.templates/services/ntfy.yaml`, `modules/services/ntfy.nix`, `tests/phase-la-admin-contract.sh`
  - criteria: With deny-all default access, each transition token user has exactly the required write-only publisher ACL; host names are not used as ntfy ACL users unless they are actual authenticated user names.
  - delegate: CoderAgent
  - verify: Ciphertext-safe generated-config contract proves token users and ACL subjects agree, auth file, deny-all default, and exactly three write-only transition publishers render; standard checks pass.

- [x] 3.2d Require valid bcrypt hashes for declarative ntfy token users.
  - refs: `secrets/.templates/services/ntfy.yaml`, `modules/services/ntfy.nix`, `tests/phase-la-admin-contract.sh`
  - criteria: Every template-defined token user has the documented `username:bcrypt-hash:user` shape; the operator creates a disposable password hash and `tk_` token locally, then encrypts both as server configuration.
  - delegate: CoderAgent
  - verify: Template and ciphertext-safe contracts reject empty password-hash token users; standard checks pass.

- [x] 3.2e Harden and document the canonical generic host-initialization path before further migration operations.
  - refs: `docs/runbooks/host-initialization.md`, `.just/host-age.just`, `secrets/justfile`, `deploy.sh`, `.sops.yaml`, `docs/architecture.md`, `modules/profiles/shell-profile.nix`, `modules/core/users.nix`, `modules/shared/host-recovery.nix`
  - criteria: The adoption path documents observed RAM-based `/build` sizing, facter versus filesystem/bootloader ownership, fingerprint-verified SSH-host-key-to-age derivation, validation gates, deploy-rs handoff, and a separate public-cutover boundary; the reimage path names the repo entrypoint and cannot derive a persistent recipient from a temporary installer key; secret re-encryption recipes cover YAML and JSON; unsafe live-keyscan recipient updates are removed or fail closed; the first configured boot provides `dev`'s managed Zsh startup without interactive new-user setup while `root` and console-only `rescue` retain minimal Bash recovery shells with no operator Zsh configuration.
  - delegate: `CoderAgent`
  - verify: Focused script/recipe and shell-account regressions, `just fmt-check`, `just checks all`, `git diff --check`, and `openspec validate --strict` pass.

- [x] 3.2f Fail closed on every Kanidm offline verification failure.
  - refs: `modules/services/admin/kanidm.nix`, `tests/kanidm-restore-contract.sh`, `tests/phase-la-admin-contract.sh`, `specs/kanidm-identity/spec.md`, `design.md` MIG-5
  - criteria: The stopped, version-matched restore helper treats every nonzero offline verification result as fatal before ownership repair or manual service start; it accepts a verification only when the verifier exits zero, carries its clean-success marker, and reports no error-bearing output; routine non-error startup/reindex diagnostics are permitted only on that clean path; temporary verifier output is removed on every exit path; there is no accepted `RefintNotUpheld(<id>)` or db-scan non-live finding class.
  - delegate: `CoderAgent`
  - verify: Focused restore-helper regressions prove clean success and rejection of every nonzero/failed offline verification shape (plain failures, RefintNotUpheld-only findings, findings alongside routine diagnostics, mixed errors, and error markers) before ownership repair; `just checks all`, `just fmt-check`, `git diff --check`, and strict OpenSpec validation pass.

- [x] 3.2g Remove hostname-derived Tailscale advertise-tags and make role tags key-owned.
  - refs: `modules/services/tailscale.nix`, `tests/phase-la-admin-contract.sh`, `docs/runbooks/host-initialization.md`, `docs/runbooks/admin-host-migration.md`, `specs/network-access/spec.md`, `design.md` MIG-1
  - criteria: `services.tailscale.extraUpFlags` retains the stable node hostname but does not derive `--advertise-tags` from `networking.hostName`; server role tags come only from the operator-created tagged auth key; LA uses the established `tag:homelab` and `tag:ssh-clients` roles that the outgoing admin host already has; host-scoped tag claims are removed from migration and initialization guidance.
  - delegate: `OpenDevopsSpecialist`
  - verify: The LA contract proves `services.tailscale.extraUpFlags` contains `--hostname=la-admin-1` and no `--advertise-tags`; exhaustive scoped search finds no `tag:<host>` or `tag:la-admin-1` contract; `just checks all`, `just fmt-check`, `git diff --check`, and strict OpenSpec validation pass.

- [x] 3.2h Add the LA-only Tailscale SSH key-exchange compatibility workaround.
  - refs: `lib/deploy/hosts.nix`, `lib/deploy/default.nix`, `.github/workflows/deploy-host.yml`, `tests/phase-la-admin-contract.sh`, `specs/network-access/spec.md`, `design.md` MIG-2c
  - depends: 3.2g
  - criteria: Physical deployment metadata supplies `-o KexAlgorithms=curve25519-sha256` only for LA; deploy-rs, CI's additional strict known-host options, and the post-deploy notification SSH call retain the host option; no Tailscale enrollment, role-tag, MTU, firewall, public-port, or other-host SSH settings change; documentation names a successful fresh default ML-KEM session after a Tailscale update as the removal gate.
  - delegate: `OpenDevopsSpecialist`
  - verify: Focused evaluation proves only LA carries the override through deployment and post-deploy wiring; `just _activate la-admin-1` reaches dry activation over Tailscale without switching services; LA writers and timers remain quiesced; `just checks all`, `just fmt-check`, `git diff --check`, and strict OpenSpec validation pass.

- [x] 3.2i Tolerate only the proven Kanidm v1.10.4 revoked-OAuth verifier false positive.
  - refs: `modules/services/admin/kanidm.nix`, `tests/kanidm-restore-contract.sh`, `tests/phase-la-admin-contract.sh`, `docs/runbooks/admin-host-migration.md`, `specs/kanidm-identity/spec.md`, `design.md` MIG-5
  - depends: 3.2f
  - criteria: The stopped restore helper accepts a nonzero verifier result only for exactly `RefintNotUpheld(319)` on Kanidm 1.10.4, after independent read-only `db-scan` checks prove the `idx_eq_oauth2_session` entry, `RevokedAt` session state, and `rs_uuid` all match the known missing resource server `05e3c021-5b84-417e-8d4c-ed2f2d9c88b7`; every version/output-shape mismatch, additional finding, failed scan, or other verifier failure remains fatal before ownership repair or service start; the helper never mutates or quarantines database state to pass.
  - delegate: `CoderAgent`
  - verify: Focused regressions prove clean success, the exact accepted condition, and rejection of wrong version, wrong finding/id/UUID/session state, malformed or missing scan output, additional errors, and every existing generic failure shape; real-binary CLI contracts cover `version`, `database verify`, and both `db-scan` forms; independent security review plus `just checks all`, `just fmt-check`, `git diff --check`, and strict OpenSpec validation pass before one LA restore retry.

- [x] 3.2j Make Kanidm provisioning readiness local to the host before public cutover.
  - refs: `modules/services/admin/kanidm.nix`, `tests/phase-la-admin-contract.sh`, `specs/kanidm-identity/spec.md`, `design.md` MIG-5
  - depends: 3.2i
  - criteria: Kanidm's provision/start readiness and provisioning client use the upstream local `https://localhost:<bind-port>` default, retaining its loopback-only invalid-certificate allowance. They SHALL NOT require Cloudflare DNS, Authenticated Origin Pull client credentials, or a public edge route before the restored target can start.
  - verify: LA's evaluated provision URL is `https://localhost:8443`, its local invalid-certificate allowance is enabled, the focused LA contract and standard checks pass, and an independent review reports no unresolved high- or medium-severity finding before one service-start retry.

- [x] 3.2k Own the dev home XDG base structure in the users module so first-boot tmpfiles can create service leaf directories.
  - refs: `modules/core/users.nix`, `modules/profiles/shell-profile.nix`, `CONVENTIONS.md`, `docs/runbooks/host-initialization.md`
  - depends: 3.2j
  - criteria: `modules/core/users.nix` declares the standard XDG base directories for `dev` (`.config`, `.cache`, `.local`, `.local/share`, `.local/state`) as `d`-type tmpfiles rules owned `dev:users` 0755; service modules own only their leaf directories under that chain (wezterm keeps only `/home/dev/.local/share/wezterm`); the convention and the first-boot name-resolution limitation of home-path tmpfiles rules are documented in `CONVENTIONS.md` and the host-initialization runbook.
  - notes: Root cause of the LA `wezterm-mux-server` crash loop: first-boot tmpfiles ran before the `users` activation created `dev`, leaving `/home/dev/.local{,/share}` root-owned and the leaf uncreated, so the mux server could not bind its HOME-fallback socket. `d` rules reconcile existing ownership on the next tmpfiles pass; one `systemd-tmpfiles --create` (or reboot) heals LA after deploy.
  - verify: `nix eval` of a host's `systemd.tmpfiles.settings` shows the user-homes rules; `just fmt-check`, `just checks all`, `git diff --check`, and strict OpenSpec validation pass.

- [x] 3.2l Disable Quantum on LA for the initial cutover and permit la-admin-1 server-side OIDC discovery through Cloudflare.
  - refs: `hosts/la-admin-1/default.nix`, `modules/applications/admin/default.nix`, `modules/services/admin/quantum.nix`, `tests/phase-la-admin-contract.sh`, `opentofu/cloudflare/config.auto.tfvars`, `opentofu/cloudflare/main.tf`, `policy/web-services.nix`
  - depends: 3.2k
  - criteria: Quantum is disabled on `la-admin-1` and the LA contract asserts that deferred state; the admin application stack and OIDC topology are otherwise unchanged. Quantum is deferred until it has real priority and a private-issuer or post-cutover path is available. Because LA is the US-based admin and edge host, the Cloudflare country allowlist explicitly permits AU, GB, and US rather than accumulating per-service exceptions; all other countries remain blocked. The cache-host skip remains for EU remote builders. The ntfy activation failure is NOT addressed here — its restored bare-hostname contract and operator-owned ciphertext reconciliation are tracked under task 3.2m.
  - notes: `podman-quantum.service` server-side OIDC discovery to `https://id.shrublab.xyz/.well-known/openid-configuration` exposed the obsolete AU/GB-only assumption: LA's US egress needs the same country policy as the US-based edge and admin services. Quantum was low-priority and not reliably functional before.
  - verify: `nix eval .#nixosConfigurations.la-admin-1.config` shows Quantum disabled; the country allowlist is exactly AU, GB, and US; no LA-only OIDC skip rule remains; `tofu fmt` on `opentofu/cloudflare/main.tf`; `just fmt-check`, `just checks all`, `git diff --check`, and strict OpenSpec validation pass. Operator applies the Cloudflare rule via `just tofu plan && just tofu apply` before the next LA deploy.

- [x] 3.2m Restore bare-hostname ntfy publishers as the canonical contract.
  - refs: `hosts/la-admin-1/default.nix`, `modules/services/ntfy.nix`, `secrets/.templates/services/ntfy.yaml`, `tests/phase-la-admin-contract.sh`, `openspec/changes/migrate-admin-host-to-la/`, `openspec/changes/normalize-fleet-boundaries/`, `docs/runbooks/`
  - depends: 3.2l
  - criteria: Every ntfy ACL subject uses bare hostnames (`la-admin-1:*:write-only`, `oci-melb-1:*:write-only`, `do-admin-1:*:write-only`) matching DO's existing proven convention. No alternate service-account prefix remains in repo code, tests, templates, active OpenSpec artifacts, or documentation. The encrypted secret contract (`secrets/.templates/services/ntfy.yaml`) uses bare-hostname `auth-users` entries. The ntfy module validators and contract tests assert bare-hostname shape. The deferred `normalize-fleet-boundaries` change SHALL use bare-hostname publisher identities rather than reintroducing an alternate convention. No ciphertext is created, decrypted, or edited.
  - notes: An unrequested alternate service-user naming scheme was introduced during task 3.2c (2026-08-12) without explicit approval. It cascaded through ACL subjects, template contracts, bcrypt validators, and tests. The existing DO convention (bare hostname as ntfy username) was never broken; the added convention created a ciphertext-to-code gap that caused the LA activation failure.
  - verify: A targeted repository search proves no ntfy-auth publisher identity uses an added service-account prefix (unrelated `notification-daemon` references are excluded); `just fmt-check`, `just checks all`, `git diff --check`, and strict validation of both active OpenSpec changes pass.

- [x] 3.2n Remove the duplicate cache country-firewall skip rule.
  - refs: `opentofu/cloudflare/main.tf`
  - depends: 3.2l
  - criteria: `zone_firewall_custom.rules` contains exactly one `skip_cache_subdomain_zone_firewall` rule, retaining both cache hostnames so EU remote builders remain exempt from the country restriction. No unrelated firewall rule changes.
  - verify: `tofu fmt opentofu/cloudflare/main.tf`, `git diff --check`, and a structural search prove exactly one cache skip rule remains.

- [x] 3.3 Create LA encrypted secrets and external control-plane prerequisites from the reviewed templates as the operator.
  - refs: `.sops.yaml`, `secrets/.templates/`, `secrets/justfile`, Tailscale ACL policy, Cloudflare R2, OpenTofu runtime secrets
  - depends: 3.2g
  - criteria: The operator verifies the host-key fingerprint before deriving `&la_admin_1_age`, creates a new LA outbound `identity/ssh_private_key`, adds its public key to the central fleet trust set, re-encrypts every approved moving scope, creates an LA Tailscale auth key carrying the existing `tag:homelab` and `tag:ssh-clients` role tags, creates the LA R2 target, creates the LA ntfy token, preserves existing identity/OIDC values, and prepares the ignored Cloudflare origin input.
  - notes: User-owned; never decrypt or edit secret payloads through the agent.
  - verify: Operator confirms `sops updatekeys` completion; `just checks all` passes; LA joins the tailnet as `la-admin-1` with `tag:homelab` and `tag:ssh-clients`; and the host can read only its declared runtime secrets after deployment.

- [x] 3.3a Reconcile the operator-owned ntfy publisher ciphertext with the restored bare-hostname contract.
  - refs: `secrets/.templates/services/ntfy.yaml`, `secrets/services/ntfy.yaml`, `secrets/hosts/la-admin-1/system.yaml`, `modules/services/ntfy.nix`
  - depends: 3.2m
  - criteria: The encrypted ntfy configuration retains the existing bare-hostname publisher users and tokens for OCI and DO, and includes a bcrypt-backed `la-admin-1` user plus its publish token. The LA host `ntfy_token` equals that `la-admin-1` token. Existing human-admin credentials remain unchanged unless the operator intentionally rotates them. No agent decrypts, inspects, edits, or transmits secret payloads.
  - notes: This corrects the previous unapproved naming divergence. It is a narrow operator-owned re-encryption, not a rotation or replacement of the working OCI/DO publisher identities.
  - verify: Operator confirms the encrypted files were reconciled and re-encrypted; after the next deployment, `ntfy-sh.service` is active and LA/OCI private publish checks succeed.

## 4. Deploy and prove LA privately

- [x] 4.1 Apply the first LA generation through its existing password-sudo account with a source-controlled boot activation, then reboot through the provider console.
  - refs: `lib/deploy/default.nix`, `lib/deploy/hosts.nix`, `modules/core/base.nix`
  - criteria: `nixos-rebuild boot --target-host <initial-user>@216.75.75.168 --use-remote-sudo --flake .#la-admin-1` is the one-time first activation; the original console session remains available for the reboot; no manual `dev` user configuration is maintained outside the flake.
  - verify: First boot/reboot and key-based `dev` SSH succeeded. A corrected Zsh startup generation is staged with `boot`; it MUST remain unrebooted until task 4.3 restores state and permits writers to start. Complete the managed-Zsh, Tailscale, rescue, and deploy-rs dry-activation checks as part of tasks 4.2–4.4.

- [x] 4.2 Make deploy-rs the normal LA deployment path after first-boot access validation.
  - refs: `lib/deploy/default.nix`, `lib/deploy/hosts.nix`, `justfile`
  - depends: 4.3 — a real deploy-rs activation starts enabled services and therefore MUST NOT run against unrestored LA state.
  - criteria: LA's normal deployment target is `dev@la-admin-1` over Tailscale; the public bootstrap address is no longer the regular management path; `just _activate la-admin-1` is the non-mutating preflight and `just deploy la-admin-1 --verbose` is a real activation only after restored state is safe to start.
  - verify: `just _preflight la-admin-1` and `just _activate la-admin-1` succeed during the restore window; after task 4.3, `just deploy la-admin-1 --verbose` succeeds without the password-sudo account.

- [x] 4.3 Establish the LA backup repository and restore a recent DO snapshot for read-only private validation.
  - refs: `modules/services/state-backups.nix`, `modules/services/admin/kanidm.nix`, `modules/services/admin/vaultwarden.nix`, `modules/services/ntfy.nix`
  - depends: 3.3a
  - criteria: Before any restore or subsequent reboot, stop the LA Kanidm, Vaultwarden, Termix/guacd, Quantum, Beszel hub, ntfy, and restic state-backup services; stop the restic-backup, host-recovery-reboot, and nh-clean timers and verify that each is loaded, remains inactive, and has no next trigger throughout the restore window; retain Tailscale. The stopped LA Kanidm restore helper uses a version-matched portable export, runs offline verification, fixes ownership when required, and permits service start only after restore; its domain, identity, provisioning, and OIDC inputs match DO. Vaultwarden uses export plus state, Termix/Beszel state restores, and ntfy auth is recreated declaratively from SOPS (no direct-copy restore); Quantum is intentionally empty; no LA instance accepts authoritative writes.
  - verify: Record the scoped service/timer quiesce status before restore; use fresh DO restic snapshot `1696626a` (2026-08-14 04:51:39 UTC, capturing `backup-2026-08-14T03:15:00.269389987Z.json.gz`) for the rehearsal; Kanidm admin login, Vaultwarden login/attachment read, Termix, Beszel, and ntfy tests succeed over private access.

- [x] 4.4 Validate cross-host identity, edge, notification, cache, recovery, and resource behavior before public cutover.
  - refs: `hosts/oci-melb-1/default.nix`, `policy/web-services.nix`, `modules/shared/kanidm-host-auth.nix`
  - criteria: OCI OIDC clients, ntfy publishing, Beszel agent, Caddy certificate issuance, all declared edge routes, and LA memory behavior are verified while Cloudflare still points to DO.
  - verify: documented pre-cutover verification matrix passes with no OOM or failed service units on LA.

- [x] 4.3a Restore the Beszel hub state from the DO backup snapshot (corrective: 4.3 execution classified the hub as a fresh instance despite the plan requiring its state restore).
  - refs: `modules/services/admin/beszel.nix`, `modules/services/beszel-agent-auth.nix`, `modules/services/state-backups.nix`
  - criteria: Restore `/var/lib/beszel-hub` from the latest DO restic snapshot to LA with the hub stopped; preserve the fresh LA `beszel_data` as fallback; restore ownership to the service user; the restored hub key must match the fleet `beszel/key` already distributed to all agents via `secrets/common.yaml`.
  - verify: beszel-hub starts clean on restored state, the LA and OCI agents reconnect, and the hub presents the DO-configured admin/OIDC settings rather than first-run defaults.

## 5. Cut over and verify public service

- [x] 5.1 Perform the planned source freeze and final state transfer.
  - refs: `design.md` MIG-4 and MIG-5
  - criteria: DO Kanidm, Vaultwarden, ntfy, Termix, Beszel, and other writers are quiesced; a final managed backup is captured and ntfy auth is recreated declaratively from SOPS; final state is restored to stopped LA services.
  - verify: final snapshot ID, ntfy declarative-auth recreation validation, and LA service start logs are recorded.

- [x] 5.2 Apply the policy-driven Cloudflare origin cutover to LA.
  - refs: `opentofu/cloudflare/main.tf`, `opentofu/cloudflare/variables.tf`, `opentofu/justfile`, `scripts/render-opentofu-cloudflare-runtime.sh`
  - criteria: The ignored OpenTofu runtime origin input changes to `216.75.75.168`; public records remain policy-derived; dashboard edits are emergency-only and reconciled immediately.
  - verify: OpenTofu plan/apply succeeds and the shared origin record resolves to LA.

- [x] 5.3 Run the public cutover and rollback-ready verification matrix.
  - refs: `policy/web-services.nix`, `policy/identity.json`, `modules/services/notification-daemon/`
  - criteria: Public HTTPS, AOP, Cloudflare Access, Kanidm discovery/login, Paperless/Karakeep OIDC, Vaultwarden, ntfy, Beszel, and all declared routes work through LA; DO remains startable and routable as rollback before any unplanned rollback attempt.
  - depends: 5.3a, 5.3b, 5.3c
  - verify: record successful checks for every policy route and one end-to-end notification from each active host.

- [x] 5.3a Route cross-host ntfy dispatch through the public Cloudflare route with an explicit User-Agent and a policy-derived server URL.
  - refs: `hosts/oci-melb-1/default.nix`, `hosts/la-admin-1/default.nix`, `hosts/do-admin-1/default.nix`, `modules/services/ntfy.nix`, `modules/services/notification-daemon/default.nix`, `pkgs/notification-daemon/notification_api/main.py`, `policy/web-services.nix`
  - criteria: The notification daemon sets an explicit `User-Agent` on every ntfy HTTP request so Cloudflare Browser Integrity Check does not block them; `services.notification-daemon.ntfy.serverUrl` defaults to the policy-derived ntfy public URL (`config.repo.web.catalog.ntfy-admin.publicUrl`) rather than a hardcoded host; origin hosts (`la-admin-1`, `do-admin-1`) override to loopback while OCI uses the derived default; the public ntfy route and base URL remain unchanged; no WAF exception, Tailscale Serve endpoint, public listener, or secret rotation is introduced.
  - delegate: CoderAgent
  - verify: focused host contract tests prove the policy-derived server URL and the User-Agent header, then an OCI `notify` call reaches LA ntfy successfully.

- [x] 5.3b Cap the LA-to-OCI Tailscale tunnel MTU below the proven packet-size black hole.
  - refs: `hosts/la-admin-1/default.nix`, `hosts/oci-melb-1/default.nix`, `modules/services/tailscale.nix`, `specs/network-access/spec.md`
  - criteria: `tailscaled.service` starts with `TS_DEBUG_MTU=1200` on both `la-admin-1` and `oci-melb-1`; the workaround remains host-scoped and introduces no enrollment, identity, tag, firewall, route, or experimental PMTUD change.
  - delegate: CoderAgent
  - verify: focused host evaluations prove both daemon environments and the 1200-byte `tailscale0` MTU after deployment; the direct LA-to-OCI HTTP padding probe and every OCI-origin public edge route succeed.

- [x] 5.3c Remove the obsolete LA-only Curve25519 deployment workaround.
  - refs: `lib/deploy/hosts.nix`, `tests/phase-la-admin-contract.sh`, `.github/workflows/deploy-host.yml`, `specs/network-access/spec.md`
  - criteria: LA and OCI use default OpenSSH key-exchange negotiation; no deploy host carries a `KexAlgorithms` override; stale workaround assertions and comments are removed without changing SSH identity, authorization, or transport policy.
  - delegate: CoderAgent
  - depends: 5.3b
  - verify: a fresh `mlkem768x25519-sha256` session to LA succeeds over Tailscale, then focused deployment metadata tests, `just checks all`, and strict OpenSpec validation pass.

- [x] 5.3d Delete tautological contract tests and retain only behavioral/contract checks.
  - refs: `tests/`, `.just/checks.just`
  - criteria: Checks that merely restate file contents or mirror configuration literals (grep-a-literal, eval-mirrors-config, AST-pinned constants) are removed; retained checks validate independent expectations such as secret-scope coverage, catalog export freshness, argument-injection rejection, and gate logic; `checks all` wiring matches the retained set.
  - verify: `just checks all` passes with the reduced suite.

## 6. Establish LA recovery and retire DigitalOcean

- [x] 6.1 Run and verify the first LA-managed backup and recovery drill.
  - refs: `modules/services/state-backups.nix`, `docs/architecture.md`
  - criteria: LA writes a successful backup to its distinct repository; restore evidence covers Kanidm, Vaultwarden, and ntfy; the source R2 repository remains retained.
  - verify: `just backups run la-admin-1`, `just backups status la-admin-1`, `just backups logs la-admin-1`, and restore evidence are recorded.

- [x] 6.1a Harden the backup surface and document the canonical restore path.
  - refs: `modules/services/state-backups.nix`, `modules/services/postgres-shared.nix`, `modules/services/admin/vaultwarden.nix`, `.just/backups.just`, `docs/architecture.md`, `docs/runbooks/state-restore.md`
  - criteria: PostgreSQL uses a logical export rather than raw live-directory coverage; Vaultwarden export staging exists declaratively; restic monitors notify on failure; active contracts contain real paths with explicit exclusions; a safe restore-staging recipe and one canonical runbook cover Kanidm, PostgreSQL, Vaultwarden, Beszel, ntfy, and the remaining backed-up service state with minimal manual steps.
  - delegate: CoderAgent, DocWriter, CodeReviewer
  - verify: host backup-contract evaluation, focused export/restore contracts, `just fmt-check`, `just checks all`, and strict OpenSpec validation pass.

- [x] 6.2 Decommission the DO infrastructure after the 24-hour soak window.
  - refs: DigitalOcean console, `.sops.yaml`, Tailscale admin console
  - criteria: A final DO snapshot is retained, then the droplet and chargeable attached resources are destroyed; the DO tailnet device is revoked only after LA is authoritative.
  - notes: Operator-owned infrastructure action. Operator confirmed all criteria complete: final DO snapshot retained, droplet/resources destroyed, DO tailnet device revoked after LA authoritative.
  - verify: DO billing resources show only intentionally retained recovery artifacts.

- [x] 6.3 Remove the legacy DO host and recipient after retirement.
  - refs: `hosts/do-admin-1/`, `modules/providers/digitalocean/`, `flake.nix`, `lib/deploy/hosts.nix`, `.sops.yaml`, `.github/workflows/`, `.just/`
  - criteria: No active topology, deployment, CI, policy, secret reader, or documentation reference treats DO as an active host; stale DO-only provider configuration is removed; the operator re-encrypts after recipient removal.
  - delegate: CoderAgent
  - verify: `just fmt-check && just check && openspec validate migrate-admin-host-to-la --strict`
