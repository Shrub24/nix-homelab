# Host Initialization Runbook

Canonical bring-up path for a new fleet host. Per-host values (addresses, keys, UUIDs) live in the host migration runbook or captured facts; this runbook is generic. Migration-specific runbooks reference this file rather than duplicating it.

Two entry states, one steady state:

1. **Adopt** an existing provider-installed NixOS system non-destructively.
2. **Reimage** a host that is not NixOS, or whose disk layout must be replaced.
3. **Steady state** via `deploy-rs` after the first source-controlled generation.

## 1. Choose adoption vs destructive reimage

Observe the target before touching it. Adopt only when every check holds; otherwise reimage.

| Check | Adopt | Reimage |
|---|---|---|
| OS is NixOS | yes | no |
| Disk layout is safe to keep (root + ESP by stable IDs) | yes | unsafe, missing, or needs repartition |
| Existing boot works and can be preserved | yes | no / bootloader conversion risk |
| Install is the one we want to operate | yes | throwaway provider image |

Reimage is also the default when the target needs encryption, repartitioning, or a different bootloader. `nixos-anywhere` and `disko` are installation tools, not adoption tools — never run them against a live adoptable volume.

## 2. Capture facts

Run `nixos-facter` as root on the target, single-host report, no `--swap` or `--ephemeral`:

```sh
nix run github:nix-community/nixos-facter -- -o facter.json
```

- review and commit `hosts/<host>/facter.json`; consume it directly via `hardware.facter.reportPath = ./facter.json`
- do not share or regenerate the report on another node
- record runtime facts separately: `nixos-version`, `uname -m`, `lsblk -f`, `findmnt`, `df -h`, `ip -br addr`, `ip route`, EFI/boot mode, data-mount availability, the initial sudo account, and the provider-console reboot procedure
- record RAM and build-plane capacity: `free -h`, `swapon`, `nproc`; size the `/build` tmpfs from the observed RAM, never from another host's defaults
- stop before writing host networking until these are captured

### Fact ownership: facter vs filesystem vs bootloader

- **facter owns** hardware, drivers, virtualisation, and DHCP — consume the report directly, and do not hand-maintain driver, virtualisation, or network-interface configuration beside it.
- **filesystem mounts are not reported by facter** — hand-maintain only the observed root and ESP by-UUID mounts required to preserve the existing installation.
- **bootloader ownership is explicit, not inherited** — an adopted host preserves its existing bootloader (e.g. UEFI `systemd-boot`); do not let the fleet base module's default (GRUB removable media) override a working installation. Record the boot mode and confirm the preserved bootloader selects the new generation.

## 3. Verify the SSH host key, then derive the age recipient

- confirm the provider-console fingerprint matches `/etc/ssh/ssh_host_ed25519_key.pub` on the target
- confirm the root filesystem preserves that host key across reboots
- derive the recipient only from the verified persistent host key; never regenerate the verified key, never guess
- keep the verified fingerprint in the runbook before recipient derivation

Recipe workflow (`.just/host-age.just`):

- `just host-age get <host>` prints the age recipient from a **live `ssh-keyscan` result — diagnostic preview only**. A keyscan result is not verified against the provider console and must never be persisted.
- `just host-age from-key '<ssh-ed25519 AAAA...>' key_alias=<host>_age update=true` persists the anchor. Before running it, verify the supplied public key matches the provider-console fingerprint (e.g. `scripts/ssh-known-hosts.sh verify <host> <fingerprint> <key-line>` or `ssh-keygen -lf` on the on-target `/etc/ssh/ssh_host_ed25519_key.pub`). Never paste an unverified keyscan result.

Host keys are the machine's decryption identity for sops-nix; the anchor becomes the host's SOPS identity for the lifetime of its ciphertext.

## 4. Three key identities

| Identity | Ownership | Purpose |
|---|---|---|
| Host age key | existing persistent SSH ed25519 host key, converted to the age recipient | machine decryption identity |
| Operator auth keys | `modules/core/users.nix` | human SSH login |
| Outbound identity | new per-host `identity/ssh_private_key` secret; public half added once to the central fleet trust set | `dev` reaching fleet peers |

The three identities are separate. Never reuse another host's outbound identity; two live hosts sharing a principal is not acceptable.

## 5. Operator-owned handoff: secrets, Tailscale, R2, recovery

The operator creates and encrypts — never the agent, never automation:

- host secret ciphertext from repository templates (system, OIDC, service hashes/tokens)
- a tagged Tailscale auth key carrying the established fleet role tags for that host (baseline `tag:homelab`, plus role-specific tags such as `tag:ssh-clients` where needed)
- the host-scoped R2 backup repository
- host ntfy token if required

Repository changes provide policy, contracts, and templates only. The operator verifies the fingerprint before adding the host recipient to `.sops.yaml`, then re-encrypts the moving scopes. Keep blast radius host-scoped: remove transition readers from moved scopes immediately, retaining them only where the still-running rollback host actively consumes the secret.

## 6. Rescue readiness before first fleet boot

Before password SSH is disabled:

- console-only `rescue` user enabled with host-scoped password material (`secrets/hosts/<host>/system.yaml`)
- provider console verified to perform and observe a reboot
- second key-based SSH session succeeds before the original console session closes

## 7. Validation gates and first source-controlled generation (adoption)

Apply `boot`, never live `switch`, through the existing password-sudo account:

```sh
nixos-rebuild boot --target-host <initial-user>@<addr> --use-remote-sudo --flake .#<host>
```

**Before boot (validation gates):**

- `just fmt-check` and `just checks all` pass (repo formatting, secret-scope, host-phase, and restore contracts)
- the host toplevel evaluates/builds: `nix build .#host-<host>` (or the equivalent preflight gate for the change)
- `just _preflight <host>` confirms the generation declares `openssh`, tcp/22, and `dev`/`root` keys

**After reboot (boot validation):**

- declared `dev` key SSH, `tailscale status`, and console-only `rescue` login succeed
- `free -h` shows the expected memory behavior with no OOM in `journalctl -k` / failed units (`systemctl --failed`)

- no manual `dev` user or host state is maintained outside the flake — the flake is the SSOT for users and keys

Name-based home-path tmpfiles rules (e.g. `/home/dev/.config`) may fail on the first boot pass because the `users` activation has not created the user yet. That is expected and benign: the rules reconcile on the required console reboot, or run `systemd-tmpfiles --create` manually.

### Operator and recovery shells

The fleet baseline keeps shell accounts distinct by declaration, never by post-boot editing:

- `dev` is the managed interactive operator account with Zsh. Its `.zshrc` is provisioned by the `dev-zshrc` activation step, which depends on the `users` step that creates `/home/dev`, so the first configured boot is ready without interactive setup.
- `root` and the console-only `rescue` account use minimal interactive Bash (`bashInteractive`) with the shared recovery SSH keys but none of the operator Zsh prompt, plugin, or alias configuration.
- Operator aliases are Zsh-only (`programs.zsh.shellAliases`); the global `environment.shellAliases` is empty.

**First-boot validation:** a first `dev` login that enters `zsh-newuser-install` means the first generation was incomplete (the `dev-zshrc` activation did not run after account-home creation). Treat that as a failed first-boot validation — do not complete the interactive setup and do not patch dotfiles on the host. Rebuild/reboot from a fixed generation and confirm `tests/check-shell-account-contract.sh` passes before continuing.

## 8. Reimage path

- repo entrypoint: `just bootstrap <host> <addr>` runs `deploy.sh` with `hosts/<host>/bootstrap-config.nix` (which must declare `hostName`, `bootstrapUser`, `flake`, and, when hardware-config generation is wanted, `hardwareConfigGenerator` and `hardwareConfigPath` together). `deploy.sh` itself requires an explicit `--host-config <path>` and never assumes a default host; it runs `nixos-anywhere` over SSH from a temporary supported Linux image, with `disko` applying the declarative layout
- the temporary installer image's SSH host key is **diagnostic only** — it disappears with the installer and must never be used to derive a persistent SOPS age recipient
- two-step secrets bootstrap is the default: install the base system first, then, after first boot, enroll the persistent host-key recipient exactly as in sections 3–5 and create encrypted secrets
- continue from rescue readiness and first-generation steps; then deploy-rs takes over

## 9. deploy-rs steady state and public cutover

After first-boot access validation, `deploy-rs` is the normal path (`dev@<host>` over Tailscale); the bootstrap address is no longer the regular management path. Network-owner transitions are boot-time cutovers (`deploy-rs --boot` plus console reboot), never live `switch` over SSH.

**Public cutover is a separate boundary.** Routing public traffic to the host (DNS, Cloudflare origin, edge policy) is a distinct gate that happens only after private validation of the host stack, governed by the migration runbook and the edge-policy SSOT — host initialization itself never includes public exposure.
