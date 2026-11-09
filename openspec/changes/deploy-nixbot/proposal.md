# Proposal

## Why

Make nixbot on home-forge the CI and cache-reconciliation plane for `Shrub24/nix-homelab`. Replace the candidate lifecycle rather than maintaining two authorities: admission decides which builds run, GitHub owns merging, and main reconciles publication and retention.

**Core Value:** One observable build verdict and a repeatable path from admitted source to available, retained build artefacts.

## What Changes

- Fix repository discovery: remove `github.userAllowlist`, which is ORed with the repository allowlist. Use two evaluation workers at 3072 MiB and retain stock outside-contributor approval.
- Put the entire validation verdict in `checks`, including the contracts currently run by `ci.yml`. Require nixbot's `nixbot/nix-eval` and `nixbot/nix-build` from its App integration, with up-to-date branches.
- Make equal-tree PR/main outputs reusable by removing the commit revision from host output identity while retaining the tracked source at `/etc/nixos-source`.
- Add a main-only `cache-retain` effect. It depends on both architecture retention roots, pushes them idempotently and moves `nix-homelab-main-<system>` pins through scoped nixbot workload identity. Restarting the effect is the cache repair path.
- Let GitHub auto-merge green automation PRs; human PRs remain operator-merged. Keep the scheduled Actions update producer and its automation environment/App credential. Enable its auto-merge input only after the owner lands that input upstream; until then producer PRs wait for manual merge.
- **BREAKING after observed cutover:** remove the candidate lifecycle, Actions CI/build/cache callers, lifecycle ruleset/label/variables and unused CI credentials. Existing deployment workflows, tooling and their credentials remain. Retain other repositories' cache federation rules.

## Capabilities

### New Capabilities

- `nixbot-ci`: admitted multi-architecture builds, authenticated control, cache reconciliation and observed cutover/recovery.

### Modified Capabilities

- `nixbuild-build-plane`: nixbot replaces the manual Actions build path and provides the complete required verdict.
- `fleet-infrastructure`: retain tracked source provenance without commit-ID-dependent host outputs.
- `sovereign-binary-cache`: admitted CI may publish; a main-effect OIDC rule owns homelab's rolling pin namespace, while the existing static admin uploader token remains an explicitly accepted risk.

Related contracts remain `operations`, `cache-push-workflow`, `state-backups`, `postgres-shared-access` and `edge-proxy-ingress` under `openspec/specs/`.

## Impact

Extend the existing `deploy-nixbot` implementation, not a new change. Affected areas are `modules/ci/`, flake checks/effects/provenance, cache OIDC policy, secret templates/recipient rules, Renovate, GitHub settings/rulesets, workflow retirement and operator documentation. Source facts and builder capacity continue to derive from nix-fleet; this change edits no nix-fleet files.

**Constraints:** the operator alone creates/edits encrypted material; no secrets in `nixbot.toml` or flake outputs; every effect declares `secretsMap`; PR effects remain off; no extra effects branches or event effects. No deployment effect, deploy credentials, deployment-tool retirement, Kanidm, merge queue, other repositories, controller admission patch or native scheduled producer.

The stages are fixes/checks/cache effect; verified token claims and ordered cache/coordinator activation; observed green PR/merge/pins; main ruleset; then CI/candidate deletions. Post-merge reconciliation manages artefact availability and retention, not host activation. No merge without owner approval. Missing operator credentials or live evidence blocks the corresponding stage rather than completing it by inference.
