## 1. Spec generalization (storage mandate)

- [x] 1.1 Modify the storage-model requirement in `fleet-infrastructure` and `bootstrap-storage` to allow root-backed directories and media opt-in.
  - refs: `openspec/specs/fleet-infrastructure/spec.md` (Storage model separates service state and media), `openspec/specs/bootstrap-storage/spec.md` (Service-state and media mounts are separated), `openspec/changes/add-home-forge-host/specs/`
  - criteria: Both MODIFIED deltas generalize locations to mount-or-root-backed-directory with stable by-id references and media opt-in; requirement identity preserved; no other requirement changed.
  - delegate: CoderAgent
  - verify: `openspec validate add-home-forge-host --strict` passes.

## 2. Two-disk disko storage module

- [x] 2.1 Add `modules/storage/disko-two-disk.nix` (ESP + ext4 root on `disk.main`; optional ext4 bulk storage on `disk.storage` at a host-declared mountpoint; root-backed `/srv/data` and `/nix` via tmpfiles; no `bios_grub`).
  - refs: `modules/storage/disko-single-disk-split.nix`, `modules/storage/disko-single-disk.nix`
  - criteria: Module is general (host sets `disk.main.device`, `disko-second-disk` by-id, mountpoint, sizes); no host-specific literals; `/nix` and `/srv/data` are directories, not partitions.
  - delegate: CoderAgent
  - verify: `nix eval .#nixosConfigurations.home-forge.config.disko` resolves once task 3.1 lands; no OCI/Cloudflare assumptions.

## 3. home-forge host configuration

- [x] 3.1 Create `hosts/home-forge/default.nix` composing: base-server profile, the two-disk disko module, systemd-boot (Secure Boot off), DHCP networking + nameservers + firewall, `tag:homelab` Tailscale, `hasHostSecrets`-guarded host secrets, shared substitute/build-profile consumer, `system.stateVersion`.
  - refs: `hosts/oci-melb-1/default.nix` (composition pattern), `modules/profiles/base-server.nix`, `modules/services/tailscale.nix`
  - criteria: Host is thin (feature selection + explicit exceptions only); no app/workload modules (music/paperless/litellm/mcp absent); `networking.hostName = "home-forge"`; no edge role; no public ingress.
  - delegate: CoderAgent
  - verify: `nix eval .#nixosConfigurations.home-forge` succeeds; no `applications.music`/`services.paperless`/`bifrost-gateway`/`niks3`/`postgres-shared` imports.

- [x] 3.2 Wire `nixos-facter` facts (live-ISO or first-boot report) instead of hand-maintained hardware guesses.
  - refs: `hosts/oci-melb-1/hardware-configuration.nix`, STACK (`hardware.facter.reportPath`)
  - criteria: No committed hand-written hardware-configuration; facter report path is wired (operator gate 8.3 generates it — captured from the live ISO, hardware identical to first boot).
  - delegate: CoderAgent
  - verify: Host eval does not depend on a committed hardware-configuration.nix; facter wiring present.

## 4. Topology and CI (consume normalize-fleet-boundaries)

- [x] 4.1 Add `home-forge` to `lib/deploy/hosts.nix` (x86_64, marked non-deployable) and `flake.nix` `nixosConfigurations.home-forge`; exclude from `deployOrder`.
  - refs: `lib/deploy/hosts.nix`, `flake.nix`, `openspec/changes/normalize-fleet-boundaries/specs/fleet-infrastructure/spec.md` (topology SSOT)
  - criteria: `home-forge` appears in `nixosConfigurations` and topology metadata as non-deployable; absent from `deployOrder`; consumes (does not duplicate) normalize's consistency check.
  - delegate: CoderAgent
  - verify: Topology consistency check passes (home-forge marked non-deployable); `nix flake check` passes.

- [x] 4.2 Add `home-forge` to CI build/eval (x86_64) without adding it to the serial cloud deploy chain.
  - refs: `.github/workflows/ci.yml`, `.just/checks.just`
  - criteria: CI evaluates/builds `home-forge`; deploy workflow does not target `home-forge`; mismatch check (from normalize) stays green.
  - delegate: CoderAgent
  - verify: CI eval/build of `home-forge` succeeds; deploy workflow lists no home-forge job.

## 5. Secrets policy and templates (agent; no ciphertext)

- [x] 5.1 Add the `home-forge` host secret scope + recipient placeholder to `.sops.yaml` (path-bound; no implicit cross-host decryption).
  - refs: `.sops.yaml`, `openspec/specs/secrets-management/spec.md` (Recipient policy is path-bound and auditable), `tests/check-secret-scope.sh`
  - criteria: `secrets/hosts/home-forge/*` paths scoped to the home-forge recipient + owner only; no other host gains access; recipient is a placeholder until operator gate 11.1 supplies the verified key.
  - delegate: CoderAgent
  - verify: `./tests/check-secret-scope.sh` passes; scope rules name only home-forge + owner for home-forge paths.

- [x] 5.2 Add `secrets/.templates/hosts/system.yaml` placeholders for home-forge (tailscale auth key, backup R2 creds + restic repo password, rescue password hash) and document the contract.
  - refs: `secrets/.templates/hosts/system.yaml`, `openspec/specs/secrets-management/spec.md` (Host system secret template; Backup repository credentials SHALL remain host-scoped)
  - criteria: Template carries documented placeholders only; no live secret values; the agent does NOT decrypt, edit ciphertext, encrypt, or deploy secrets.
  - delegate: CoderAgent
  - verify: `git diff` shows template placeholders only; no ciphertext file created/edited by the agent.

## 6. Backup and recovery wiring

- [x] 6.1 Wire `services.state-backups` for home-forge (host-scoped R2 bucket, `stagingRoot = /srv/data/state-backups`, host system secret); backup scope = core/high-level state, workload paths deferred.
  - refs: `modules/services/state-backups.nix`, `hosts/oci-melb-1/default.nix` (state-backups block), `openspec/specs/secrets-management/spec.md` (Backup transport defaults; host-scoped creds)
  - criteria: home-forge opts into host-scoped backup; staging on `/srv/data`; creds resolve from `secrets/hosts/home-forge/system.yaml`. Deviation note: baseline-only host has no workload-contributed backup paths, so a core-state entry (`services.host-core.paths = ["/etc/ssh"]`) is registered to satisfy the module's non-empty-payload assertion — host identity, not workload scope.
  - delegate: CoderAgent
  - verify: `nix eval` of home-forge `services.state-backups` matches contract; no cross-host secret scope.

- [x] 6.2 Wire `services.hostRecovery` (host-scoped rescue operator + recurring reboot exercise); document physical console as primary break-glass.
  - refs: `modules/shared/host-recovery.nix`, `hosts/oci-melb-1/default.nix` (hostRecovery block), `openspec/specs/host-recovery/spec.md`, `openspec/specs/network-access/spec.md`
  - criteria: home-forge opts into recovery baseline; rescue material from host system secret; physical console documented as break-glass; no `host-recovery` spec change.
  - delegate: CoderAgent
  - verify: `nix eval` of home-forge `services.hostRecovery` is enabled with a recurring reboot exercise.

## 7. Repository validation

- [x] 7.1 Run full validation and record apply-ready status.
  - refs: `treefmt.toml`, `.just/checks.just`, `flake.nix`, `openspec/`
  - criteria: `just fmt-check`, `nix flake check`, `just checks all`, `nix eval .#nixosConfigurations.home-forge`, and `openspec validate add-home-forge-host --strict` pass; no secret ciphertext created/decrypted/edited by the agent.
  - delegate: BuildAgent
  - verify: Validation report saved; strict OpenSpec validation passes.

## 8. Operator gate — ISO boot and fact collection

- [x] 8.1 Boot the NixOS live ISO on home-forge (HP Z2 G4); collect `/dev/disk/by-id` for the NVMe and HDD, the LAN MAC, and the DHCP IP.
  - refs: `modules/storage/disko-two-disk.nix`, STACK (stable by-id inputs)
  - criteria: by-id values for both disks + MAC + IP recorded by the operator and fed into host config / disko device options.
  - delegate: Operator (manual)
  - verify: Host config `disk.main.device` and `disko-second-disk` reference the collected by-id values.

- [x] 8.2 Confirm destructive-install acknowledgment (both disks wiped; unencrypted).
  - refs: `proposal.md` (Constraints)
  - criteria: Operator explicitly acknowledges data loss before `nixos-anywhere`.
  - delegate: Operator (manual)
  - verify: Acknowledgment recorded in the change notes.

- [x] 8.3 Generate the `nixos-facter` report from the live ISO or first boot and wire `hardware.facter.reportPath`.
  - refs: STACK (`hardware.facter.reportPath`), `hosts/home-forge/default.nix` (task 3.2)
  - criteria: Facter report committed/wired; host eval uses captured facts, not guesses.
  - delegate: Operator (manual)
  - verify: `nix eval .#nixosConfigurations.home-forge` succeeds with the facter report in place.

## 9. Operator gate — secret material and R2

- [x] 9.1 Create the `home-forge` R2 bucket and restic repository; generate the restic repository password.
  - refs: `services.state-backups` (task 6.1), `openspec/specs/secrets-management/spec.md` (Backup repository credentials SHALL remain host-scoped)
  - criteria: R2 bucket + restic repo exist; repo password generated; transported out-of-band to the operator.
  - delegate: Operator (manual)
  - verify: Bucket reachable; restic repo initialized (`restic snapshots` against the repo).

## 10. Operator gate — base install (no secrets)

- [x] 10.1 Run `nixos-anywhere` over LAN with the home-forge disko config (destructive); base system converges without host secrets.
  - refs: `modules/storage/disko-two-disk.nix`, `hosts/home-forge/default.nix`, `openspec/specs/secrets-management/spec.md` (Two-step bootstrap secret flow)
  - criteria: Disks partitioned per disko; base NixOS boots; secret-dependent services (tailscale auth, backup, recovery) remain dormant via the `hasHostSecrets` guard.
  - delegate: Operator (manual)
  - verify: Host boots to a login prompt over LAN; `systemctl is-system-running` passes.

## 11. Operator gate — persistent host key and ciphertext

- [x] 11.1 Verify the persistent SSH host key at the local console; derive the age recipient via `ssh-to-age`; replace the `home-forge` placeholder recipient in `.sops.yaml`.
  - refs: `openspec/specs/secrets-management/spec.md` (Host recipient derivation is operationalized), `openspec/changes/normalize-fleet-boundaries/specs/host-recovery/spec.md` (verified host-key-to-age)
  - criteria: Host key verified at the physical console (not over an unverified network path); age recipient derived and registered; existing recipients unaffected.
  - delegate: Operator (manual)
  - verify: `just host-age from-key '<console-verified public key>' key_alias=home_forge_age update=true` replaces the placeholder; scope checks pass.

- [x] 11.2 Create ciphertext secrets for home-forge (tailscale `tag:homelab` auth key, R2 access/secret keys, restic repo password, rescue password hash) — operator encrypts; agent does not touch ciphertext.
  - refs: `secrets/.templates/hosts/system.yaml` (task 5.2), `.sops.yaml` (task 5.1)
  - criteria: Encrypted `secrets/hosts/home-forge/system.yaml` created by the operator from the template after the verified recipient is registered; no plaintext committed; agent did not decrypt/edit/encrypt.
  - delegate: Operator (manual)
  - verify: `sops --decrypt secrets/hosts/home-forge/system.yaml` succeeds operator-side; `git diff` shows only encrypted data.

## 12. Operator gate — step-2 local deploy

- [x] 12.1 Push secrets and run the local rebuild switch over LAN (`nixos-rebuild switch --target-host`).
  - refs: `hosts/home-forge/default.nix`, STACK (nixos-rebuild --target-host for post-install updates)
  - criteria: Secret-dependent services activate; home-forge reaches its intended baseline state.
  - delegate: Operator (manual)
  - verify: `tailscale status` shows home-forge with `tag:homelab`; backup service + recovery timer active; no public ingress.

## 13. Operator gate — verification

- [x] 13.1 Verify baseline: Tailscale up (`tag:homelab`, no public ingress), recovery baseline active (rescue operator + reboot timer), backup dry-run succeeds on core state.
  - refs: `openspec/specs/network-access/spec.md`, `openspec/specs/host-recovery/spec.md`, `services.state-backups` (task 6.1)
  - criteria: Tailscale tagged and private; recovery timer scheduled; `restic backup --dry-run` covers core state and stages no workload paths.
  - delegate: Operator (manual)
  - verify: Operator verification report attached to the change.

## 14. Final review gate

- [x] 14.1 Review the complete change for boundary, security, and rollback defects.
  - refs: `proposal.md`, `design.md`, `specs/`, `tasks.md`
  - criteria: No app migration invented; no speculative provider module; no ciphertext touched by the agent; spec deltas are MODIFIED-only (no competing requirements); alignment with `normalize-fleet-boundaries` confirmed.
  - delegate: CodeReviewer
  - verify: Review report shows no unresolved high/medium finding; change declared apply-ready.

## 15. Fleet-standard profile wiring (post-review addition)

- [x] 15.1 Extract duplicated fleet tooling into `modules/profiles/fleet-standard.nix` and consume it from all hosts.
  - refs: `modules/profiles/fleet-standard.nix`, `hosts/home-forge/default.nix`, `hosts/la-admin-1/default.nix`, `hosts/oci-melb-1/default.nix`, `flake.nix`, `modules/core/users.nix`
  - criteria: nh GC, nixbuild-ssh, niks3-auto-upload/post-deploy, beszel-agent-auth, hostIdentity, and the niks3 API token registration live in the profile with conventional secret paths derived from `networking.hostName`; la-admin-1/oci-melb-1 drop their duplicated blocks (oci keeps its loopback serverUrl override); home-forge gains the `niks3-auto-upload` flake module; home-forge outbound dev identity pubkey added to `modules/core/users.nix`.
  - verify: all three hosts eval with every flag true and correct upload URLs; home-forge + la-admin-1 toplevels build locally; `just checks all` PASS; strict validation PASS.

- [x] 15.2 Enable the notification daemon on home-forge.
  - refs: `hosts/home-forge/default.nix`, `.sops.yaml`, `tests/fixtures/secret-scope.nix`
  - criteria: `services.notification-daemon` enabled with service-scoped secrets (`secrets/services/notification-daemon.yaml`, re-encrypted by the operator to include the home-forge recipient) and host-system secrets; ntfy publishes over the tailnet to la-admin-1; monitor enabled with an empty service list until workloads land.
  - verify: eval shows enable/ntfy/monitor true; secret-scope 17/17 PASS; toplevel builds; strict validation PASS.
