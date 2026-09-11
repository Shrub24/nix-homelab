# Context And History

This document summarizes the current project context and the key transition history that led to the present architecture direction.

## Historical Starting Point

The repository originally focused on a single `dev-vps` workflow centered around:

- developer-oriented shell and Home Manager customization
- CodeNomad access workflow over Tailscale
- custom `repo-sync` workflow for private local state orchestration
- provider assumptions aligned with earlier single-host operations

That direction produced working components, but it was optimized for a different objective than the current homelab fleet target.

## Explicit Direction Pivot

The project direction was intentionally changed to:

- Oracle Free Tier as the first host target
- DigitalOcean as a second host provider target
- modular reproducible NixOS multi-service architecture
- host-fleet thinking over single-machine developer workflow
- Tailscale as mandatory private connectivity fabric
- initial practical focus on media stack (`navidrome` + `syncthing`)

The previous `dev-vps` and `repo-sync` emphasis was explicitly de-prioritized for this repository.

The admin/edge/identity host later moved again: `la-admin-1` is now the active x86_64 admin, edge, and Kanidm/OIDC host, adopted non-destructively from its preinstalled NixOS system, with `do-admin-1` retained as an undeployed rollback source until the LA backup/recovery gates pass and it is decommissioned.

## Research And Validation Outcomes

During planning and research, the selected direction was validated as idiomatic and modern for current NixOS workflows:

- `nixos-anywhere` for remote host bootstrap
- `disko` for declarative disk layout
- host-centric flake/module structure
- reusable service modules behind explicit enable flags
- private service exposure first, public edge later

Tooling stance that emerged:

- keep first host path simple
- bootstrap remains `nixos-anywhere`, while regular updates now use `deploy-rs`
- preinstalled NixOS systems are adopted non-destructively per the canonical runbook (`docs/runbooks/host-initialization.md`), with `nixos-anywhere`/`disko` reserved for the destructive reimage path
- structure repository now so later tooling adoption is low-friction
- keep host bootstrap/secret workflows host-key driven with clear default and advanced variants

Operational lesson captured during `do-admin-1` networking recovery:

- the host had been running on provider/cloud-init-managed static network state rather than `dhcpcd` or `systemd-networkd`
- migrating that host to declarative `systemd-networkd` required matching the observed static `ens3`/`ens4` addresses instead of assuming DHCP
- the failed attempt was caused by doing a live SSH `switch` during network-owner handoff; the cutover succeeded when installed with `deploy-rs --boot` and applied on reboot

Follow-on recovery lesson captured during host-recovery implementation:

- the real missing break-glass path was a console-capable password-authenticated local user, not another normal SSH identity and not an immediate initrd SSH rollout
- the chosen baseline is a console-only `rescue` user plus a weekly reboot exercise, with initrd SSH deferred until host-specific early-boot networking assumptions are worth validating separately
- recovery secret wiring was intentionally moved into the shared recovery module so hosts stay thin and feature-owned secret contracts remain the norm
- local validation is asymmetric: `do-admin-1` can be built on the x86_64 admin machine, while `oci-melb-1` may still require host-side or remote validation when non-substitutable `aarch64-linux` derivations prevent a full local build

## Security And Secrets Direction

The conversation converged on blast-radius secrets management:

- common shared secrets are separated from host-specific secrets
- host-scoped decryption policy is preferred by default
- per-host enrollment tokens are preferred to shared reusable credentials

Bootstrap nuance that was discussed in depth:

- two-step secret bootstrap is default for lower early-stage risk
- pre-generated host identity is allowed but treated as advanced and sharper

## Service And Data Direction

Current operational posture chosen in planning:

- one persistent data mount
- one dedicated `/nix` filesystem on the recovered `oci-melb-1` single-disk layout
- Syncthing bidirectional mode with safety/versioning controls
- Navidrome reads directly from sync-managed media path
- no duplicate staging dataset initially to avoid unnecessary storage usage

Recovery lesson now captured in active context:

- a live migration that removed the old `/nix` before the new mount was boot-valid broke the host hard enough to require OCI rescue-instance recovery
- the validated break-glass repair path was: attach boot volume to rescue VM, mount root + `/nix` + ESP, chroot with working `/dev` `/proc` `/sys` `/run` + DNS, build with sandbox disabled where needed, then run `switch-to-configuration boot`
- the resulting declarative baseline for `oci-melb-1` is a single OCI boot volume carrying labeled filesystems for `/`, `/srv/data`, `/nix`, and `/srv/media`
- shared media root directories are now intended to have one canonical tmpfiles owner in the application composition layer, with lower-level services only layering ACL or marker behavior

Future-facing but deferred:

- `rclone`/VFS authority model
- file processing hooks and worker-style automation

## Network And Exposure Direction

Chosen posture:

- Tailscale-only exposure for now
- public exposure options remain future considerations, not baseline requirements

## Cleanup And Migration Intent

The migration intent is intentionally aggressive:

- remove legacy assumptions and obsolete docs/code paths tied to old mission
- keep only what is still relevant to the new fleet-oriented target
- avoid long-lived dual-mission repository drift

## Dendritic Transition Decision (2026-09)

- D-030's plain-flake restriction was superseded by D-047: the fleet adopts flake-parts plus `denful/import-tree` with named `flake.modules.nixos` aspects and a typed `nixos.configurations.<host>` registry, delivered through staged OpenSpec changes
- Stage 1 (flake-parts scaffold, all three hosts moved atomically to `modules/hosts/<host>/`, every lower-level `self`/`inputs`/`ociImages` consumer removed instead of bridged) landed in `dendritic-stage-1-scaffold-hosts`
- Stage 2 landed foundation-first (2026-09-10, `dendritic-stage-2-foundation-aspects`): the five foundation aspects (`base`, `shell`, `networking`, `tailscale`, `notify`) publish through `flake.modules.nixos` with typed `fleet.foundation` host facts; `modules/core/` and `modules/profiles/` were deleted and removed from the import-tree exclusion; deferred operational behavior remained explicit raw-leaf imports in host records at that point. The former music-exemplar Stage 2 is superseded/historical; the change is implementation-complete but not deployed or archived (equivalence/validation gates pending)
- Stage 3 landed operational aspects (2026-09-11, `dendritic-stage-3-operational-aspects`): the three operational aspects (`backups`, `builder-access`, `observability-agent`) publish through `flake.modules.nixos` and are selected by all three registry hosts; the five deferred operational leaves (state-backups, niks3-upload-client, niks3-post-deploy, nixbuild-ssh, beszel-agent-auth) fold under them and are no longer host imports; `backups` derives the conventional host secret path and bucket, gates on the secret file's existence, injects the post-deploy filter package per system, and asserts the notify-owned monitor option without importing `notify`; the classified `post-build-hook = mkForce ""` suppression is retained (upstream `niks3-auto-upload` has no hook-disable option); the OCI cache server stays a leaf and `services`/`shared` remain temporarily excluded. The change is implementation-complete but not deployed or archived (equivalence/validation gates pending); see D-049. Stage 4 (`dendritic-stage-4-source-model-realignment`, D-050) then realigned the documented model: source ownership and deployment granularity are independent axes, the central `modules/flake/aspects.nix` was replaced by concern-owned discovered contributors, `provenance`/`oci-images`/`fleet-packages` are classified as infrastructure support, `dj` selection enables `applications.dj`, and plain class-oriented leaves plus the six-directory filter are transitional rather than the endpoint
- `flake-file`, Den, and topology extraction are deferred; `nix-fleet` is a future code-only library for proven reusable aspects, while concrete topology, web-services policy, OpenTofu, deploy-rs metadata/order, `.sops.yaml` readership, and encrypted secrets remain owned by this repository
- the 2026-08-30 transition analysis was revalidated 2026-09-09: the music move to `home-forge` already completed (D-045/D-046, so it is not Stage 2 future payoff), Engine DJ added a real `inputs` consumer, home-forge is an intentional deploy-rs node with committed facter, and Stage 0 pre-clean removed the dead paperless application wrapper, the orphan `.just/deploy.just` module, and `mkSimpleSecret`

## Current Truth Snapshot

As of this planning update:

- first host name is fixed: `oci-melb-1`
- active admin/edge/identity host is fixed: `la-admin-1`
- second host name is fixed: `do-admin-1`, retained only as an undeployed rollback source until decommission
- serial deploy order is `la-admin-1` before `oci-melb-1`; `do-admin-1` is absent from `deployOrder` and CI
- the local-admin Cockpit public path is `cockpit.shrublab.xyz/la-admin-1`
- cross-host consumers resolve stable service IDs through the policy catalog (`config.repo.web.catalog`); physical deployment facts (`edgeHost`, `deployOrder`) stay only in `lib/deploy/hosts.nix`
- LA adoption of its preinstalled NixOS system is separate from later AU edge and US-East workload work
- canonical runbooks: `docs/runbooks/host-initialization.md` (generic bring-up) and `docs/runbooks/admin-host-migration.md` (LA transfer facts)
- Open WebUI deployment is deferred until the migration cutover and backup gates pass
- architecture direction is fleet-first, modular, and native-service-first
- active host path is `hosts/oci-melb-1/default.nix`
- active admin host path is `hosts/la-admin-1/default.nix`
- rollback host path is `hosts/do-admin-1/default.nix`
- active provider boundary is `modules/providers/oci/default.nix`
- active storage boundary is `modules/storage/disko-root.nix`
- active single-disk storage boundary is `modules/storage/disko-single-disk.nix`
- active reusable module boundaries are the concern-owned aspect contributors under `modules/flake/` (foundation `base`/`shell`/`networking`/`tailscale`/`notify`, operational `backups`/`builder-access`/`observability-agent`, application `dj`) plus the infrastructure support modules (`provenance`, `oci-images`, `fleet-packages`), private implementations under `modules/flake/_aspects/`, the `tailscale` service leaf (`modules/services/tailscale.nix`), and the remaining shared leaves (`modules/shared/`)
- legacy `nixos/configuration.nix`, `nixos/digitalocean.nix`, and `nixos/disko-config.nix` are retired from active architecture
- decisions have been formalized in `docs/decisions.md`
- strategic planning posture is maintained in `docs/plan.md`
- architecture intent and boundaries are in `docs/architecture.md`

This context document exists to preserve why the repository changed, so future implementation steps stay aligned with the intended direction.
