# Nixbot CI/cache implementation brief

## Scope

Nixbot on home-forge replaces nix-homelab's CI and candidate lifecycle. It builds admitted PR checks and uploads outputs; GitHub owns merging; main reconciles publication and rolling retention pins. **Deployment remains separate.** No deploy effect, deploy-tag trigger/ruleset, deploy key or deployment-tool deletion is included.

This extends `deploy-nixbot`. No nix-fleet edits, encrypted-payload edits, live activation, ruleset changes, commit, push or merge have been performed for this cutover. The production gate remains off, and the operator identifiers/key are unconfigured. Old CI/candidate workflows remain until observed acceptance permits retirement.

## Implemented surface

- `modules/ci/nixbot.nix`: pinned upstream coordinator, GitHub OAuth, signed webhooks, loopback listener/private TLS front, dedicated builder identity, PostgreSQL/backup/notification integration and native streaming uploader. Owner-wide discovery was removed; only homelab is admitted. Two evaluators use 3072 MiB with IFD disabled.
- `tests/nixbot-contract.nix` (wired by `modules/ci/checks.nix`): real selected-module configuration, effective admission against sibling/foreign repositories, evaluator bounds and named failures for missing inputs. This focused contract passed.
- `modules/flake/repository-contracts.nix` and `scripts/run-repository-contracts.sh`: the existing shell battery becomes an isolated buildable check with a writable source/store. Local `just checks all` shares the same test list. The isolated VM suite built green on the final tree.
- `modules/ci/cache-retain.nix`: untagged-main-only effect, both architecture roots as dependencies, `cache` lock, explicit empty secrets map and scoped workload audience. Each root is pushed before its rolling pin moves. A failed push aborts; restarting repeats reconciliation without a changed-input skip.
- `modules/cache/niks3-cache.nix`: exact repository/main/push/effect-bound nixbot OIDC rule, write scope and only `nix-homelab-main-*` pins. Existing grants remain during cutover. The expected effect claim is `default.cache-retain`; a real issued token must confirm it before trust activation.
- `tests/cache-retain-contract.nix` (wired by `modules/ci/checks.nix`): evaluated selection, dependency and trust constraints plus the real script against a stubbed client for partial failure and repeatable repair. It also asserts the Nix CLI the real client invokes and the rule at the native server boundary; it passed on the final tree.
- `modules/flake/provenance.nix`: tracked `/etc/nixos-source` retained, commit-ID stamping removed. Two different scratch commits with one source tree produced identical derivations/source paths for **all three hosts**, with null configuration revisions. This is not an observed nixbot PR/main reuse test.

The pinned niks3 client accepts `--auth-token-script` for both push and pins; pins help text is stale. Both operations use the native short-lived token helper. No temporary token-file workaround is needed.

## Authority and accepted risks

The UI uses application authentication for the whole hostname, not partial Cloudflare Access. Public project reads may be anonymous; controls require authorization. Stock admission holds untrusted forks for Approve CI. PR effects remain off; there are no event effects, per-repository effect secrets or writable mountables.

The uploader retains the accepted static **admin** token and could move pins. Normal reconciliation uses scoped OIDC, but that does not reduce the uploader's authority. Lost webhooks require a rerun/next push, not assumed replay. Admitted builds share home-forge with the controller, with the sandbox as the boundary. No deployment authority is added.

## Not yet available or proven

- Production App login/webhooks and repository scheduling: no approved activation or credentials.
- Nixbot-driven ARM execution: both retention roots were built locally with the ARM root built on `oci-melb-1` over the operator's existing SSH access, which validates the build only. Builder-side nixbot evidence and clean-store substitution remain unobserved.
- Real-token claim/signature verification and PR/other-effect rejection: pending, not established by local claim fixtures.
- Nixbot ARM execution, clean-store substitution, green PR/merge reuse and moved rolling pins: unobserved.
- Cache-outage/restart and stopped-controller delivery recovery: unobserved. The runbook records these as pending separately from expectations.
- App-sourced main checks, automation auto-merge and CI/candidate retirement: gated on the observed cutover. Human PRs remain operator-merged.
- Producer auto-merge input: waits for the owner's nix-fleet change; no unsupported input is passed here.

## Next stages within this change

1. Finish and review local checks, final-tree formatting/freshness/IFD-off evaluation, and both root builds using an approved ARM path.
2. Operator provisions App/OAuth/webhook, builder key and uploader token, then fills the non-secret policy. Resolve the real-token bootstrap prerequisite explicitly; a disabled issuer cannot supply observed token evidence. Deploy verified cache trust before the first normal main effect, then activate the coordinator through existing deployment tooling.
3. Observe PR/fork approval, ARM execution, substitution, owner-approved merge reuse and pin movement; perform the coordinated outage/token/downtime experiments and record actual results.
4. Configure App-sourced required checks and GitHub auto-merge. Enable the agreed Renovate classes and the producer's supported auto-merge input when available.
5. Retire only CI/candidate callers, lifecycle configuration and genuinely unused credentials. Keep the scheduled producer, `deploy.yml`, `deploy-host.yml` and their credentials. Run the final nothing-references-retired-tooling and repository gates.

No merge without owner approval. Detailed staging and acceptance are in `tasks.md`; activation, repair, rollback and the observation register are in `docs/runbooks/nixbot.md`. D-113 and D-114 preserve the superseding rationale without rewriting historical decisions.
