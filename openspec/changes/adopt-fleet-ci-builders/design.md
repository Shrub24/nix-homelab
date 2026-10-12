# Design

## Context

See `proposal.md` for motivation. The consumer already imports `flakeModules.fleet` through `modules/flake/builder-access.nix`; profile artifacts and canonical host trust exist. That contributor deliberately renders trust only. `modules/flake/base/foundation.nix:81` trusts root/dev but not a build account. All three hosts select `cache-publisher`, which imports the shared `niks3-publisher` mechanism.

The CI workflows still use `.github/actions/setup-nixbuild/` and `NIXBUILD_STORE`. `justfile:78-93` contains legacy prebuild entrypoints, including a missing `host-home-forge` package and a missing `nix-path-filter` output. The specs also retain a CI-push prohibition and post-build-hook suppression that conflict with adoption; the deltas resolve those contradictions rather than implementing both policies.

The upstream inspection used revision `6c26cce9fd2f898bfcf8e41fcc94c5ee791ddc0b`, the owner's intentional `nix flake update` result. Only the `nix-fleet` node moved (`e6025838` → `6c26cce9`); `modules/fleet`, `lib/build-profile.nix` and `docs/contracts/builders.md` are unchanged at this revision, so the account, profile and trust findings above still hold. The working tree had drifted from the Git index, which `.#` reads; the index is now staged to the same revision so evaluation and the workflow reference can be pinned together. The telemetry rollout is independent, and a builder deployment must not start while it is in flight.

## Goals / Non-Goals

**Goals:** thin consumer bindings, one canonical profile, real remote-build and publication evidence on both architectures, and no separate local CI implementation.

**Non-Goals:** host-to-host offload, metered build services, workload relocation, cache-retention changes, automatic deployment, or reusing a build key for deployment.

## Decisions

### FB-1 — Keep canonical inventory and profile projections upstream

Use `config.fleet` from this evaluation and the published pure projections. Preserve `builder-access` as trust only; do not reconstruct machine records or copy the fixture realization. `packages.<system>.ci`, `cache-api-url` and `ci-tailscale` are already supplied by the imported feature.

The canonical profile gives home-forge 4 jobs/speed 2, OCI 4 jobs/speed 2, and LA 2 jobs/speed 1. LA's weight is not strict priority or a RAM limit; no profile tuning is invented in this change. Do not select `arm-expensive`, which includes a metered external builder. Separate architecture profiles would duplicate a filter Nix already applies.

### FB-2 — Add one account convention contributor

Add `modules/flake/build-account.nix`, publishing our `build-account` aspect. It imports `inputs.nix-fleet.modules.nixos.build-account` and closes over flake-parts `config.fleet.ci.sshPublicKey` to authorize the NixOS account. Select it explicitly in all three host records. No local copy of the account mechanism, no host-inline public-key literals, and no bundling account creation into outbound trust.

The upstream account has a working Bash shell for ssh-ng; its prose saying “no shell” is not the implementation. Preserve the mechanism, do not replace its shell with nologin. The forced-dispatch A/B experiment established that ssh-ng requires the dispatch account in `nix.settings.trusted-users`: an identical tiny ARM derivation failed under `nixbuild` while copying an unsigned input, then succeeded as root. The selected nix-fleet `build-account` aspect owns the name-derived trusted-users binding; this repository must not duplicate it. Trusted-user membership is effectively root-level Nix authority, even without sudo, so retain the single canonical coordinator key and the existing SSH/Tailscale admission boundaries. Do not describe the account as a sandbox.

### FB-3 — Schedule only from CI by default

The upstream workflow installs the `ci` machines artifact. `resolve.buildMachines` is an optional NixOS sink, not an enabled aspect. Hosts keep `nix.buildMachines = []` and distributed builds off, matching both upstream's opt-in model and the user's acceptance of CI-only distribution. This avoids daemon credentials on every host and self-scheduling loops. No unused scheduling option is added locally.

### FB-4 — Call the matching reusable workflow

At this revision the reusable workflow is one coordinator job (`prepare`, then `build`): there is no separate GitHub-native build job, and the coordinator installs the niks3 action for its own local builds. Pin `.github/workflows/build-push-cache.yml` to the same immutable revision as the flake input — do not assume the `v1` tag carries this contract. Forward `FLEET_BUILDER_SSH_KEY` as `BUILDER_SSH_KEY`, grant `contents: read`/`id-token: write`, keep `builder_attr = ci`, and let the workflow resolve cache and federation metadata.

Input selection is disjoint and must not be conflated: `runner_system` picks the coordinator architecture (default aarch64), `systems` selects target-architecture branches (default both), and `builder_attr` selects remote capacity (`ci` by default, empty for local-only). A foreign-architecture target cannot fall back to the coordinator, so keeping both systems selected and the `ci` profile non-empty is what makes one ARM coordinator build the fleet's mixed-architecture set.

`targets` is now a single flake selection, and the nix convention — which the workflow also defaults to — is `.#checks`. Consume that rather than a custom aggregate or a per-host matrix. Our `checks` currently carries validation only: `deploy-activate` comes from deploy-rs's `deployChecks` and is a single derivation with no input derivations, so it does not reach the host activation closures, while the host profiles live in the `packages.host-*` allowlist that omits home-forge entirely. Standardise by publishing each host's activatable profile as a `checks.<system>.<host>` entry for all three hosts, so one call with both target systems builds the whole deploy surface. Accept the consequence that a plain `nix flake check` then builds those system closures locally; evaluation-only gates use `--no-build`, which the degoog import-from-derivation makes load-bearing on a cold store. Keep validation in the repository's own job: formatting, contracts, generated-flake freshness and flake checks. Address the degoog IFD at the real gate boundary rather than hiding it behind a successful command chain or removing checks to pass.

Validation runs for PRs and existing push coverage, with main added for publication. Privileged build/publication runs only after validation on main pushes or main dispatch. Fork and branch PRs never receive builder credentials or tailnet access. This matches the cache's existing main-only bound claims; no claim widening is needed.

### FB-5 — Verify every publication path

The workflow contributes no upload implementation of its own: the coordinator's local builds publish through the niks3 action's GitHub-OIDC hook, and remote builders publish through their host-owned post-build hooks. The earlier revision's locally-realized-wrapper gap is closed upstream by the action, which also replaced the legacy token refresher; the host-side mechanism is unchanged, so preserve the existing shared publisher and host token bindings and verify their hook and daemon wiring on every builder.

Do not equate a green workflow with complete cache coverage. First dispatch must show the exact deploy-profile outputs and dependencies are cached, and must distinguish which paths the coordinator realized locally from which ones a fleet builder produced. If coverage fails because of the upstream workflow, report it upstream and hold acceptance; do not copy/fork that workflow or add a second consumer upload implementation in passing.

For each architecture, use a small deliberately uncached derivation to prove dispatch and builder hook publication. Then obtain its output from a clean consumer with builds disabled and signature enforcement intact. Include a GitHub-native upload probe, unauthorized-claims rejection, and clean substitution of the exact deployment profiles.

### FB-6 — Preserve deployment identity and remove legacy build plumbing

The build workflow only builds and caches. Retain manual deploy-rs and LA-before-OCI fail-fast ordering. Remove nixbuild setup and credentials from deployment's validation and prebuild steps; preflight the exact cached deploy profile with builds disabled before activating. Keep the existing operator development route usable for uncached local changes, rather than making every workstation deployment substitution-only.

Tailscale admission for deployment remains separately authorized. Do not assume `ci-tailscale` permits the deployment workflow, broaden its federated identity, or authorize the coordinator key as dev/root. The existing deploy workflow has never run and its identity provisioning is an operator prerequisite for live GitHub deployment acceptance. It may be configured without exercising it as part of the first build dispatch; report that distinction clearly.

Remove `.github/actions/setup-nixbuild/`, its workflow call sites, `NIXBUILD_STORE`, and the broken legacy prebuild recipes. Keep simple exact-output `nix build` entrypoints and `just deploy`; do not add an unused profile selector for future daemon offload. Do not delete nixbuild.net from the shared substitute catalog: that catalog is upstream-owned and independent of selecting an external builder.

## Risks / Trade-offs

- **Cold-store evaluation** → degoog's module evaluates through an import-from-derivation whose generator is a `runCommandLocal` (`allowSubstitutes = false`), so a coordinator with an empty store cannot evaluate home-forge without building it locally and an evaluation-only gate fails there. The gate currently passes only because a warm local store already holds that output. Verify the CI target set from a cold store, and treat the upstream IFD as the fix — not a suppressed check.
- **Publication lag or coordinator-realized wrappers** → clean substitution is the acceptance gate, not upload log text alone. The coordinator's local outputs publish through the action's OIDC hook, so a missing path is an upstream defect rather than an expected gap; report it and hold closeout.
- **Nix daemon trusted account is powerful** → authorize only the canonical coordinator key, document effective privilege, preserve host-key checking, and verify revocation. No private material enters Nix evaluation or source control.
- **LA has limited RAM; advertised concurrency is not a memory cap** → use upstream defaults initially and measure first dispatch; report resource failures rather than silently declaring a larger supported feature set.
- **Tailnet join, builder SSH and cache OIDC are separate controls** → verify each independently. Secret presence is not proof of its value; the operator confirms the coordinator fingerprint out of band.
- **Index/working-tree pin disagreement** → the intentional update is reconciled and staged; keep the flake pin and the workflow revision moving together, and stop if a future revision changes gateway placement unexpectedly.
- **Privileged PR execution** → do not use pull_request_target or forward credentials into PR code.
- **Legacy spec drift** → replace only the build/cache requirements this adoption changes; unrelated historical cleanup is not part of implementation.

## Migration Plan

1. Keep the already-reconciled fleet lock (`6c26cce9`) staged so `.#` and the workflow reference agree, and re-check that no further upstream drift appeared before editing. Confirm the telemetry rollout's outcome and selected baseline; refresh this plan if that contract differs.
2. Land the account bindings, host selections and focused observable tests. Review this stable checkpoint before touching overlapping files.
3. Verify metadata, profile artifacts, cache policy, publisher hooks and account permissions; deploy account changes to builders sequentially, with normal rollback protection.
4. Confirm operator-provisioned coordinator key and Tailscale federation/ACLs. Run an authorized manual main build dispatch with recorded run IDs and output paths.
5. Verify remote and GitHub-native publication and clean signed substitution. Enable normal main-push publication after first-dispatch acceptance.
6. Remove legacy build plumbing, preserve the manual deployment boundary, update docs and TD-30, and run the parent gate battery.

Rollback disables the caller build job and revokes the coordinator key on builders; it does not delete cached objects or mutable service state. Previous host generations remain available. GitHub deployment remains blocked until its distinct identity is provisioned and tested.
