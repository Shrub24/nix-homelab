# Dendritic Transition — Architecture Scoping Report

Date: 2026-08-30. Revalidated: 2026-09-09. Baseline: live `main@origin` post fleet-consolidation (oci-melb-1, la-admin-1, home-forge).
Status: scoping report, not an OpenSpec change. This analysis supersedes the `normalize-fleet-boundaries` design; surviving items from that change are absorbed into the stages below.

## Revalidation (2026-09-09)

Dated revalidation against the live repository during `dendritic-stage-0-pre-clean`. Where this section contradicts the 2026-08-30 body, this section wins; body rows called out as historical below remain as scoping evidence.

- **Hosts unchanged:** the live flake is still plain `nixosSystem` × 3 (`oci-melb-1`, `la-admin-1`, `home-forge`) with `specialArgs = { self; inputs; ociImages; }`. No flake-parts or Dendritic code exists yet; Stage 1 is decided, not implemented.
- **Music migration is complete, not future payoff:** the OCI→forge move already landed via D-045/D-046 (host-selected music root on `home-forge`, AudioMuse DB in OCI). The Stage 2 "payoff" framing below is historical; the portability thesis still awaits a post-scaffold placement move.
- **Argument consumers grew since scoping:** the original "`inputs` has zero module consumers; `self`/`ociImages` replaceable by lexical policy imports" row is superseded. `inputs` now has a real consumer (Engine DJ's `traktor-m3u-sync` module and package in `modules/applications/dj/engine-dj.nix`); `self` consumers include `modules/core/base.nix` (source provenance), `shared/niks3-post-deploy.nix`, `music/beets`, `notification-daemon`, `paperless`, and `dj`; `ociImages` consumers include phoenix, karakeep, bifrost, omniroute, tagr, audiomuse, termix, quantum, and paperless-gpt. Per D-047, Stage 1 must eliminate these consumers (aspect closure, `perSystem`/`withSystem`, typed OCI policy, `inputs.self` provenance) rather than bridge them through `specialArgs`.
- **Settled Stage 1 structure (D-047):** flake-parts + `denful/import-tree`; aspects via `flake.modules.nixos.<aspect>`; typed `nixos.configurations.<host>` registry; all three hosts migrate atomically to `modules/hosts/<host>/`; host-private/raw files excluded from import-tree; plain leaf modules temporarily behind an explicit `import-tree.filterNot` boundary. `flake-file`, Den, and topology extraction are deferred.
- **import-tree ownership/semantics:** the helper is `denful/import-tree`; underscore-prefixed path components are excluded by its default filter.
- **`nix-fleet` rule:** future code-only library. Candidates only: Tailscale, SSH, builder access, Nix defaults, selected shell defaults, notification daemon/dispatch, niks3 post-build/post-deploy integration, Beszel agent. Extraction requires a verified local aspect plus materially identical behavior needed by both repos. Topology/inventory, `policy/web-services.nix`, domains/exposure/Cloudflare policy, OpenTofu, deploy-rs metadata/order, `.sops.yaml` readership, and encrypted secrets stay owned by `nix-homelab`.
- **Stage 0 landed:** dead `modules/applications/paperless/` wrapper deleted (Paperless continues through `modules/services/paperless/` directly), orphan `.just/deploy.just` deleted (the root justfile owns the `deploy` recipe directly), unused `mkSimpleSecret` deleted, and the AudioMuse credential comments now match D-045's accepted two-file model. Deferred by design: OCI music-cutover soak residue, the litellm role question, and the notification composition gap.
- **home-forge is intentional, not drift:** it is a deploy-rs node by design (kept outside the serial `deployOrder`), and `modules/hosts/home-forge/facter.json` is committed and wired via `hardware.facter.reportPath`; the flake's "no facter report yet" comment above the `home-forge` system is stale code residue, not a missing fact file.

## Verdict

The repo should move to **plain flake-parts + import-tree + named `flake.modules` aspects**, keeping leaf NixOS modules almost entirely unchanged behind a new composition surface. Den is deferred. The refactor is real — today the flake is hand-rolled `nixosSystem` with broad `specialArgs` — but roughly 80% of `modules/services/**` survives verbatim; what actually changes is `flake.nix`, `hosts/`, `modules/applications/`, `modules/profiles/`, and the secret-registration contracts.

The transition is worth doing now because the operational roadmap (edge split from admin, postgres placement, InboxZero/degoog/OpenWebUI arrivals) is exactly the workload-placement churn that today forces host-file surgery. (Scoping-time list; the music OCI→forge move has since completed via D-045/D-046 — see Revalidation.) Without the refactor we would encode placement, secret bindings, and endpoint literals a second time during those migrations and rewrite them again afterwards.

## Current state (evidence, not vibes)

| Fact | Evidence |
| --- | --- |
| No flake-parts; `flake.nix` hand-defines 3 `nixosSystem`s with `specialArgs = { self; inputs; ociImages; }` | `flake.nix` |
| (historical, superseded 2026-09-09) `inputs` specialArg had **zero** module consumers; `self`/`ociImages` consumers were judged replaceable by lexical `import ../../policy/...` — Engine DJ has since added a real `inputs` consumer | discovery pass over all modules; see Revalidation |
| Host files are wiring boards: oci-melb-1 275 lines (sops re-registration, podman firewall port binds, postgres consumer flags, monitor unit lists naming other features), la-admin-1 154, home-forge 165 | `hosts/*/default.nix` |
| Host identity triplicated: flake `nixosConfigurations` keys, `lib/deploy/hosts.nix`, `.sops.yaml` anchors (`oci_melb_1_age` etc.) + CI/test literals; only `deploy-host.yml` and the secret-scope test derive from SSOTs | cross-cutting pass |
| Repeated verbatim in all 3 hosts: `sops.defaultSopsFile`, `tailscale_auth_key` block, TS debug-MTU and `/build` 50% overrides | profile pass |
| Composition gap: `state-backups.nix` references `services.notification-daemon.monitor.enable`, but no profile imports notification-daemon — every host must remember | profile pass |
| `core/base.nix` forces GRUB; 2 of 3 hosts `mkForce` it off for systemd-boot. `core/users.nix` is hand-imported by all hosts instead of arriving via baseline | profile pass |
| `modules/applications/paperless/` is dead code — a parallel never-enabled config path beside direct `services.paperless` on OCI | admin/edge pass |
| Only cockpit is genuinely independently placeable today; kanidm, vaultwarden, termix, beszel, gatus, homepage, webhook all gate unconditionally on `applications.admin` | admin/edge pass |
| `applications.music` is a real composition: 6 leaf services, shared uids 975–977, `music-ingest`/`music-media` groups, one backup contract, event chains (slskd settle → ingest → beets → navidrome rescan) | music pass |
| Audiomuse DB-password SSOT split: home-forge reads `music.yaml:audiomuse/postgres_password` while `audiomuse.nix` comments claim `postgres-shared.yaml` is SSOT — that file's recipients exclude home-forge | music pass |
| home-forge drift: `facter.json` exists but `flake.nix:146-147` comment says it doesn't; no `deployable = false`, so it **is** a deploy-rs node today (only `deployOrder` hides it) | host pass |
| Secret duplication smells: tailscale auth key hand-rolled ×3 while `modules/services/tailscale.nix` registers nothing; cockpit password hash hand-rolled ×2 despite `admin/cockpit.nix:63-76` owning `serviceUser.hashedPasswordFile`; beszel-agent-auth declared twice on OCI | secrets pass |
| Dead tooling: `.just/deploy.just` orphaned (not imported, diverged), `mkSimpleSecret` zero callers, `secrets/opentofu/cloudflare.yaml` Nix-orphaned, `scripts/resolve-host-config.sh` parses attrs by 2-space-indent grep | blast-radius pass |

## Target model

### Mechanics

- `flake-parts` drives everything; files under `modules/` become flake-parts modules via `denful/import-tree` as their legacy directory exclusions are removed. Underscore-prefixed path components remain available for genuinely private files.
- A `nixos.configurations.<host>` submodule option declares each host's explicit target `system`, deferred `module`, and optional inline bootstrap metadata. Each record is materialized through `inputs.nixpkgs.lib.nixosSystem` with **no `specialArgs` bus**; inputs and repository paths are lexically captured by the flake-parts modules that need them.
- Public aspects are names in `config.flake.modules.nixos.<aspect>`. Merge is two-level and additive at the flake-parts level: several source files may each contribute a definition to the same aspect name (pipewire+steam→`pc`), which is the mechanism that keeps the aspect count small while files stay feature-owned.
- Class discipline: `nixos` for NixOS-targeted modules, `generic` for anything imported into other evals (the `deploy`/CI wiring), matching flake-parts `flakeModules` extras so inline and file-defined modules dedupe.
- Checks wire per-system (`filterAttrs` on the host's `system`) so `nix flake check` never cross-builds aarch64 on x86 or vice versa, and `deployChecks` runs against the same filtered node set.

### The aspect surface

Selection is enablement: a host listing an aspect in its `imports` **is** the statement "this feature exists here." Redundant `enable = true` flags die at the composition layer. Options stay for genuine variants and tuning inside a selected aspect (music's `navidrome.enable`, gateway provider choice, edge role). Cross-aspect requirements are expressed as eval-time assertions on the required aspect's exported contract — explicit selection plus assertion, never hidden transitive imports.

Proposed named aspects, with what folds into each (folded = source files contributing to that aspect, not independently selectable):

| Aspect | Contents (folds) | Justification for the boundary |
| --- | --- | --- |
| `base` | core/base, core/users, shell profile, journald, recovery/host-recovery, nix settings, timezone | every host takes it verbatim; kills manual users.nix import and the GRUB mkForce war by making boot-loader choice a host fact, not an override fight |
| `tailscale` | tailscale service + **auth-key secret contract** (default generation path derived from `networking.hostName`) + tags option | removes ×3 hand-rolled key blocks; host supplies only its tag set |
| `notify` | notification-daemon + svc-monitor + notify CLI | fixes the state-backups composition gap by owning the daemon its consumer needs; loopback-only, every host |
| `push-server` | ntfy server + its secret/file contracts | independently placed (LA today); daemon uses it but must not force it |
| `backups` | state-backups + niks3 upload/post-deploy + bucket naming from policy | one coherent "state leaves the host" story |
| `builder-access` | nixbuild SSH trust | genuinely optional per host (forge may never get it) |
| `observability-agent` | beszel-agent + auth secret contract | distinct from hub; every monitored host |
| `postgres` | postgres-shared server + roles DB + **provider/consumer connection contract** | answers the placement question with typed variants: a host either runs the provider (option) or points at a connection contract — the hybrid model grilled in batch 2 |
| `identity-provider` | kanidm server | one host; client wiring must not assume it |
| `identity-client` | kanidm host auth, ssh-group integration, per-host oidc client secret path | several hosts, no server colocation |
| `edge` | caddy ingress + role variant (edge/origin) + catalog derivation | already role-based; keep |
| `music` | navidrome, slskd, beets+ingest+reconcile, syncthing folder config, audiomuse, tagr, shared uids/groups/ACLs, backup registration, `secrets/applications/music.yaml` contract, **exported library-path contract** | the cohesive unit proven by the coupling pass; the DJ stack couples only through the exported path |
| `syncthing-runtime` | the service runtime, folders empty | generic host capability with real independent variability; music contributes folders to it |
| `dj` | windows-vm/qemu + engine-dj | separate aspect, `assertion` that music's library contract is defined — "dj belongs to music" becomes a checked requirement, not an import side effect |
| `paperless` | paperless core + gpt/llm/docling instances + postgres consumer contract + oidc client | one document-intake product; instances stay as internal variants |
| `vaultwarden`, `cockpit`, `termix` | respective services + own secret registrations | each is a distinct product with real independent placement potential |
| `observability-hub` | gatus + beszel-hub (+ homepage/webhook as internal pieces unless a split proves real) | the admin-suite remainder is a "run this on a hub host" bundle, not six products; final split decided at its conversion stage |
| `ai-gateway` (bifrost) | bifrost-gateway + provider keys + **exported gateway endpoint/model contract** | paperless-gpt consumes the contract, not the product; an omniroute aspect later exports the same contract — provider swap is a host selection change, which is what "keep it swappable" means concretely |
| `karakeep`, rest of the fleet | one aspect per product, same pattern | — |

What deliberately does **not** become an aspect: leaf NixOS modules under `modules/services/**` stay plain NixOS modules imported by their aspect. Converting ~60 leaf files into flake-parts modules is churn with zero variability gain — the dendritic win is the public aspect surface and host selection, not a ritual applied to every file. Likewise, `policy/` files stay non-module data (SSOTs read by aspects), not fake modules.

### Hosts

Host composition moves to `modules/hosts/<host>/` (settled by D-047; the earlier top-level `hosts/<name>/` path is superseded). Each host dir becomes a flake-parts module registering `nixos.configurations.<name>` with:

- the explicit aspect import list (the placement statement — 10–15 lines);
- machine facts: `system`, facter report path, filesystem UUIDs, boot-loader choice, RAM-derived `/build` tmpfs, MTU debug values as data rather than override patches;
- host exceptions, few by construction;
- `disko` layout **moved into the host directory** — the shared `modules/storage/disko-*.nix` menu is fake modularity: each layout today has exactly one consumer, and a reimage of a specific machine is a host fact;
- bootstrap metadata (reimage inputs) contributed to a flake-level data output (`flake.bootstrap.nodes.<host>`) so `deploy.sh`/`resolve-host-config.sh` do `nix eval --json` instead of grepping a Nix file by indent.

`modules/hosts/home-forge/facter.json` sits beside the host file (now committed and wired). Revalidated 2026-09-09: home-forge's deploy-rs node membership is intentional — it stays a node outside the serial `deployOrder`; no `deployable = false` is wanted. The flake's stale "no facter report yet" comment remains as code residue.

### Topology and policy

The catalog/physical seam survives and is the point: `policy/web-services.nix` + `lib/policy.nix` stay the logical service catalog (routing, Cloudflare exposure, OIDC/Access, TLS, health checks — homelab domain policy, never exported to a future fleet repo). `lib/deploy/hosts.nix` stays the physical-ops SSOT (nodes, SSH users, host-key fingerprints, `remoteBuild`, `deployOrder`, `edgeHost`, `deployable`) consumed as data by the flake-parts `deploy` wiring.

The triplication dies on the consumer side: CI matrices, `deploy-host.yml`, and test host lists derive from `nix eval` of flake outputs (`.#deploy.nodes`, host `system`s) instead of literals; `.sops.yaml` anchors cannot be derived (sops is out-of-band YAML) so `tests/check-secret-scope.sh` gains the consistency gate: derive each host's reader set from the Nix side and diff it against the sops groups, plus the already-planned deploy-order mismatch check. Dependency direction stays acyclic: nix-homelab → nix-fleet as consumer; nothing regenerates topology through CI.

### Secrets

Ownership separates from placement the way the grilling established. Each aspect owns its secret *contract*: which `sops.secrets` entries exist, their default file paths under `secrets/…`, and their consumers — registration inside `modules/services/tailscale.nix`, not the host file, is the canonical example. Placement (which host's age key must be in the recipients list) is declared once in `.sops.yaml` per bucket and verified by the scope check against the Nix-derived reader set.

Concrete consequences:

- tailscale key, cockpit hash, beszel-auth double registrations, and every `secretFiles.*` host passthrough collapse into contracts; host files lose ~all secret wiring (the F1 result from memory #516: hosts shrink toward ~40 lines because conventions are derivable).
- Moving an aspect between hosts = change the `.sops.yaml` bucket's key group + the host's aspect list; nothing about the secret's *meaning* moves.
- The audiomuse DB-password split gets one owner: the postgres aspect's per-role password contract, music.yaml drops the duplicate (or the comment lies, pick one — decision at stage 0/3 boundary, the check enforces whichever).
- `applications/` vs `services/` secret taxonomy stays; `secrets/opentofu/cloudflare.yaml` is explicitly tofu-only and removed from Nix-side scope checks rather than kept orphaned.

## The fourteen scoping questions, answered

1. **Natural aspects today** — the table above: ~18 names, built from real variability (per-host selection differences), not from systemd unit counts or current file layout.
2. **Files that fold rather than surface** — every `modules/services/music/*` leaf into `music`; shared glue (`kanidm-host-auth`→identity-client, `nixbuild-ssh`→builder-access, `niks3-post-deploy`→backups, `web-policy` wiring→edge/catalog, `host-recovery`→base); paperless gpt/docling into `paperless`; engine pieces into `dj`.
3. **Genuinely reusable independent aspects** — tailscale, notify, push-server, backups, postgres, identity-client, observability-agent, syncthing-runtime, ai-gateway. Each has ≥2 current consumers or a real placement difference between host and subscriber.
4. **Music composition** — stays one aspect. Its internals keep options (audiomuse/navidrome variants are legitimate in-feature variants); DJ detaches as `dj` with an assertion on music's exported library-path contract; syncthing splits runtime-vs-folders because the runtime is a generic capability and the folder set is music's knowledge.
5. **Host-local** — hardware facts (facter, UUIDs, RAM, MTU, boot loader), bootstrap inputs, the aspect selection list, hostnames/tags, genuine exceptions. Nothing else.
6. **Typed topology owns** — physical ops only: nodes, users, fingerprints, remote-build flag, deploy order, edge host.
7. **Domain policy stays out of topology** — web-services catalog, Cloudflare/Access/TLS/health/exposure, S3 bucket naming, gateway model config. Homelab-specific by design.
8. **Secret ownership vs readership** — aspects own contracts (registration, paths, consumers); `.sops.yaml` owns readership per bucket; CI check diffs derived-readers vs sops groups; moving placement edits the bucket group, never host files.
9. **Placement expression** — host aspect import list + assertions where a feature requires another; eval fails with a named message if a host selects `dj` without `music`. This is visibility without pretending to be a scheduler.
10. **Profiles** — `fleet-standard` was the accidental bundle it suspected being: decomposed into `base`, `tailscale`, `backups`, `builder-access`, `observability-agent`; the baseline becomes `base` + explicitly selected capabilities per host. `base-server.nix` as a composition alias dies with it.
11. **Leaf survival** — `modules/services/**` largely verbatim; deleted/absorbed: `applications/music` (becomes the aspect), `applications/admin` (splintered), `applications/paperless` (already dead), `profiles/*` (decomposed), `shared/*` glue (re-homed), `hosts/*/default.nix` (rebuilt thin). SpecialArgs removal touches only the handful of consumers that used `self`/`ociImages`, via lexical policy imports.
12. **nix-fleet intersection** — settled by D-047: `nix-fleet` is a future code-only library. Candidates (not commitments): Tailscale, SSH, builder access, Nix defaults, selected shell defaults, notification daemon/dispatch, niks3 post-build/post-deploy integration, Beszel agent. Extraction requires a verified local aspect plus materially identical behavior needed by both repositories. The aspect surface is the export interface; namespaces are the eventual vehicle. Nothing homelab-only (concrete topology/inventory, web-services policy, domains/exposure/Cloudflare, OpenTofu, deploy-rs metadata/order, secret readership) is offered upstream even as a placeholder; cross-repo topology SSOT is a separate future decision.
13. **Den** — no. Its entity/policy/quirk model pays off for cross-class fan-out (hosts→users→homes) and cross-repo aspect sharing; none of the immediate problems here (placement, secrets, thin hosts) need it — the three-host fleet is exactly the case where deferred-module merging plus host lists does the job at a fraction of the machinery. The structure chosen is den-compatible (aspects as named units, contracts as options, no ambient context), so adopting it later is a wiring change, not a rewrite. Revisit trigger: homes/users managed from this repo, a 4th config class, or nix-fleet going real.
14. **Staged boundary** — below.

## Stages

**Stage 0 — pre-clean** (behavior-preserving, one change, lands first) — executed as `dendritic-stage-0-pre-clean`; revalidated 2026-09-09:
deleted dead `modules/applications/paperless/` (Paperless continues through `modules/services/paperless/` directly); deleted orphan `.just/deploy.just` (root justfile owns the `deploy` recipe); deleted dead secret helper (`mkSimpleSecret`); corrected AudioMuse credential comments to D-045's accepted two-file model; home-forge settled as an intentional deploy-rs node with committed facter. Deferred by design (not drift): OCI music-cutover soak residue (firewall ports/monitor units/ts.net vhost), the litellm postgres role question, and the notification composition gap. Verification: `nix flake check`, `treefmt --fail-on-change`, targeted `nix-diff` on touched hosts must be empty.

**Stage 1 — scaffold + hosts** (settled by D-047): flake-parts + `denful/import-tree` + typed `nixos.configurations.<host>` registry + host dirs under `modules/hosts/<host>/` (disko and bootstrap metadata move in, `flake.bootstrap` data output lands); all three hosts migrate atomically; host-private/raw files excluded from import-tree; unconverted plain leaf modules sit behind an explicit, enumerable `import-tree.filterNot` boundary. Composition is moved verbatim — old leaf imports, no aspect renames yet. Every lower-level `self`/`inputs`/`ociImages` consumer is eliminated (no `specialArgs` bridge). Verification: `nix build` + `nix-diff` each host toplevel against pre-refactor: **must be empty**. This is the equivalence gate that makes the rest safe.

**Stage 2 — music exemplar**: build the `music` aspect surface (contracts, exports, syncthing split, dj assertion), fix the tailscale/notify secret-contract pattern in passing. `nix-diff` empty on both music hosts. (The original OCI→forge payoff move was executed before the scaffold via D-045/D-046, so the portability thesis now awaits the next real placement migration instead of a toy.)

**Stage 3 — conversion per need, migration-driven**: identity-provider/client split, admin splinter (vaultwarden/cockpit/termix/observability-hub), paperless onto contracts, postgres provider/consumer contract at the moment of any placement decision, ai-gateway contract before any gateway swap, endpoint-literal derivation from catalog. Each is a small change with the same empty-`nix-diff` equivalence gate, sequenced against the operational roadmap rather than a big-bang.

**Stage 4 — automation + closure**: CI matrices and test lists derived from flake outputs; secret-scope reader-set check; conventions rewritten to the new taxonomy (CONVENTIONS.md, ARCHITECTURE.md, STRUCTURE.md); post-transition cleanup lane (memory #514) executed; normalize-fleet-boundaries archived with its remaining tasks mapped to stages 0/3/4.

## Risks and dissent

- **Two-level merge confusion** is the main footgun: aspect-name merging is additive, option definitions inside the merged module still conflict normally. Shared aspects tune with `mkDefault`, hosts override plainly, and two aspects fighting over one option is treated as a boundary bug, fixed by restructuring rather than escalating `mkForce`. (Today's GRUB pattern is this bug at fleet scale — stage 1 must not smuggle it into the new model.)
- **Eval-diff equivalence is strict by design**; if a stage's diff is non-empty it must be explained line-by-line or the stage is wrong. Cheap (all local/remote builds are cached) and the only honest gate for a no-behavior-change refactor.
- **Sequencing against live ops**: this tree starts from `main@origin` only after the in-flight LA migration windows (4.x restore work) land; no production deploy from a mixed worktree (memory #494 still governs).
- **Where I'd push back on the source prompt**: the "singular tree, hosts folded into modules" idea is right, but pushing leaf modules into flake-parts form, auto-enabling transitive aspects, or swapping sops-nix for agenix-rekey (the reference repos' choice) are all churn without payoff — declined. The strongest version of dendritic here is *few public aspects, boring leaves, contracts at the edges, assertions instead of magic*.
- **Known ceiling**: the assertion/contract model is hand-maintained relationships (the Gaetan wireguard-peers precedent — dendritic repos don't get this free). It's the right trade at 3 hosts; it is also precisely what den's policies would later automate — one more reason the boundary is drawn where behavior demands it, not aesthetically.

## Next artifacts when approved

Stage 0 and Stage 1 as OpenSpec changes (proposal + tasks) via the normal flow; stage 2's exemplar conversion ships as its own change once 1 merges. This document is the input to those proposals and can be superseded by them on archive.
