# Tasks

## 0. Completed pilot baseline

- [x] 0.1 Retain the locally validated upstream module, local canonical-profile builder authorization, withheld route, GitHub login, database/backup/notification registrations, operator secret template and selected-module/runtime checks. Historical pilot decisions remain in design NB-1 through NB-7; NB-8 through NB-12 define this extended scope. Baseline is not live acceptance.

## 1. Fixes, checks and cache effect

- [x] 1.1 Remove `github.userAllowlist` in `modules/ci/nixbot.nix`; set two evaluation workers at 3072 MiB and IFD-off evaluation; name the reason for the peer-only setup SQL workaround. Update the nixbot contract to test effective repository admission, including rejection of another Shrub24 repository, not just list equality. Run the focused selected-module contract.
- [x] 1.2 Move the complete `ci.yml` contract job into buildable checks without silently skipping mutable-tree or negative probes. Share the existing suite between its local entrypoint and the check; retain formatting, flake/dependency freshness, hosts and packages/cache-root. Build the new suite check and run `just checks all`.
- [x] 1.3 Add the main-only cache-retain effect, explicit empty secrets map, cache lock, workload audience and both retention roots as inputs. Push before pinning, propagate failures, use the token-script JSON protocol and omit when.changed. Add focused behavior checks for main/PR/tag selection, input dependencies, empty maps and failure/repair. Build its ordinary dependencies without executing a live effect.
- [x] 1.4 Add the one-rule nixbot OIDC provider in `modules/cache/niks3-cache.nix`, retaining existing grants during cutover. Bind repository/main/push/exact effect, write and the homelab pin namespace. Verify the rendered rule and local negative-claim fixtures; reserve actual issued-token checks for stage 2/3.
- [x] 1.5 Remove revision-dependent host output stamping while retaining the tracked source copy; update affected provenance contracts and verify equal-tree derivation reuse. Record superseding decisions through keep-the-why, update the runbook/architecture/brief and run strict OpenSpec validation, all-systems IFD-off evaluation, freshness and treefmt. No nix-fleet or encrypted payload edits.

## 2. Operator provisioning and ordered activation

- [ ] 2.1 Operator provisions the App key, webhook/OAuth secrets, dedicated builder key and existing static uploader token, fills the non-secret policy and confirms App installation only for the homelab repository. No deploy key or per-repository effects secret is requested. Keep encrypted payload work with the operator.
- [ ] 2.2 Capture a real issued token, validate signature/issuer/audience and sanitized repository/ref/event/effect/sub shapes, and reconcile the exact effect claim before deploying cache trust. Explain any bootstrap ordering needed to obtain this evidence before the first main effect. Do not label source-derived or synthetic claims as observed.
- [ ] 2.3 With the required operator inputs, deploy the cache host's scoped trust before the first main effect, then enable/activate home-forge and the reviewed route through existing deployment tooling. Verify login, webhook signatures and listener isolation; update placement expectations in the enabling tree. Preserve existing CI/deployment until cutover evidence exists.

## 3. Observed CI and cache acceptance

- [ ] 3.1 Observe a PR evaluating/building both architectures, builder-side ARM execution evidence (`nix-daemon` accepted connection plus drv logs), and output substitution from a clean store. Observe a fork PR held for Approve CI and building only after approval.
- [ ] 3.2 With owner approval for the merge, observe an up-to-date PR merge reuse its build, main run cache-retain and both `nix-homelab-main-<system>` pins point to the new roots. A green source evaluation is not this evidence.
- [ ] 3.3 With coordinated outage approval, restart cache-retain while niks3 is stopped and record visible failure; recover niks3, restart the effect and observe push/pin repair. Test actual PR/other-effect tokens are refused by the cache. Record sanitized observed results, command outcomes and revisions separately from expectations in `docs/runbooks/nixbot.md`.
- [ ] 3.4 Coordinate stopping nixbot, pushing and restarting it; record what was picked up and lost, then exercise the documented rerun/next-push recovery. Keep observations distinct from upstream behavior expectations. Rehearse isolated state restore and preserve private permissions.

## 4. GitHub checks and merging

- [ ] 4.1 Configure main's ruleset to require nixbot/nix-eval and nixbot/nix-build from the actual nixbot App integration ID, with up-to-date branches and admin bypass. Enable repository auto-merge. No deploy-tag ruleset is introduced.
- [ ] 4.2 Enable Renovate platform auto-merge for the selected dependency classes. Once the owner lands an auto-merge input on the retained producer workflow, set that supported input here; until then producer PRs may require manual merge and this portion remains pending. Observe an automation PR merge on green, red checks block merging and a human PR waits for the operator.

## 5. Retire CI/candidate tooling after acceptance

- [x] 5.1 Delete `pipeline.yml`, `promote.yml`, `accept.yml`, `candidate-sweep.yml`, `fleet-build.yml`, `verify-cache.yml` and the Actions producer `package-updates-refresh.yml`, whose job the `onSchedule.package-updates` effect now does. Keep `ci.yml` (validation only), `deploy.yml`, `deploy-host.yml` and all deployment tooling. Remove pipeline/candidate adoption notes and update active architecture guidance without rewriting historical decisions.
- [x] 5.2 Remove update-candidate rules, accept-update label and obsolete PROMOTION_POLICY/CANDIDATE_*/CACHE_PIN_* variables. Remove FLEET_BUILDER_SSH_KEY or any other CI credential only when no retained caller reads it; retain deployment Tailscale credentials. The producer's automation environment/App key is no longer needed: the updater effect pushes and opens its pull request with nixbot's forge token. Remove only homelab's old build-push-cache/pin-cache OIDC grants; keep every other repository's grants.
- [x] 5.3 Run an exhaustive nothing-references-retired-tooling check, `just checks all`, all-systems IFD-off evaluation, freshness, treefmt and strict OpenSpec validation on the final tree. Confirm deployment tooling remains usable and report any unmet live acceptance item as pending. Do not merge or archive without owner approval.
