# Nixbot

## Authority and cutover status

Nixbot on home-forge is the selected replacement for nix-homelab's CI and candidate lifecycle. It evaluates and builds `checks`; GitHub owns merging; main reconciles cache publication and rolling pins. **It does not deploy hosts.** Keep `deploy.yml`, `deploy-host.yml`, operator deployment tooling and their still-used credentials.

The implementation uses nixbot `88246b4cfa43c4fb1c9cf6f78b875b3a312d31e7` against the existing fleet baseline. `policy/nixbot.nix` carries only the operator's non-secret App identifiers, the explicit `github:<login>` administrators and the separate builder public key. Selecting the aspect is the whole enablement, so evaluation fails until those values are real. Existing CI/candidate workflows and grants remain until observed acceptance and required-check configuration permit their retirement. D-113 supersedes the pilot's informative-only limit; D-114 removes commit stamping from host outputs while retaining `/etc/nixos-source`.

Local validation is not live acceptance. The observation register below is deliberately incomplete.

## Authentication and admission

The UI is `https://nixbot.shrublab.xyz`. GitHub OAuth authorizes control and private-project visibility. Public projects may be read anonymously. Cloudflare Access is off for the **entire hostname**; signed webhooks authenticate deliveries and proxy headers confer no identity. Kanidm remains deferred: the pinned login flow lacks PKCE, and no exception is introduced.

Only `Shrub24/nix-homelab` is admitted. Do not add an owner allowlist: upstream ORs it with the repository list, admitting sibling repositories. In-repository branches build with stock admission; untrusted forks wait for Approve CI. OWNER, MEMBER and COLLABORATOR are trusted associations. Evaluation uses two workers at 3072 MiB and disables IFD.

`nixbot.toml` selects `checks` with no additional build/effect branches and `effects_on_pull_requests = false`. There are no event effects, per-repository effects secrets, writable mountables or deploy keys. Every effect declares an explicitly empty secrets map.

## Operator preparation

1. Create the GitHub App using the [pinned setup guide](https://github.com/Mic92/nixbot/blob/88246b4cfa43c4fb1c9cf6f78b875b3a312d31e7/docs/GITHUB.md). Grant repository discovery/read access and check reporting, plus **contents write** and **pull requests write**, which only the scheduled updater uses: it pushes its automation branch through the checkout's origin and opens that branch's pull request. Install it only for homelab.
2. Set the homepage to the UI URL, callback to `/auth/github/callback` and webhook to `/webhooks/github` on that hostname. Prepare the App key, webhook secret and OAuth client ID/secret.
3. Prepare a separate builder SSH key. Put only its public half in `policy/nixbot.nix`. The local `nixbot-build-account` contributor derives membership from nix-fleet's canonical `ci` profile and adds the key alongside the existing coordinator key. Only home-forge gains scheduling. No nix-fleet edit is required.
4. The operator creates/edits `secrets/services/nixbot.yaml` from `secrets/.templates/services/nixbot.yaml.j2`, using the path-scoped recipient rule. It holds the App/webhook/OAuth credentials, builder private key and existing cache admin token. Agents edit only templates and recipient rules, never the encrypted payload. No deploy credential is requested.
5. Fill the non-secret App IDs and administrator in policy. Keep the production gate off until credentials, activation review and the ordered trust preflight are ready.

### Uploader authority

The streaming uploader retains the operator-accepted **static admin API token**, delivered by `LoadCredential`. It can read, write and move pins. A separate SOPS field does not make it independently scoped or revocable; rotation affects other consumers of that token. Builder trust is also effectively root-level Nix authority. Do not describe this as a least-privilege controller.

Native upload uses `niks3 push --stdin` against the private catalog endpoint. Upload failures are warn-only, so green builds alone do not establish availability. Normal main pinning uses scoped workload identity instead. No uploader credential is passed to an evaluated build or effect secret.

## Cache reconciliation

`onPush.default.outputs.effects.cache-retain` exists only for an untagged main push. It has lock `cache`, audience `https://cache.shrublab.xyz`, an explicit empty secrets map and dependencies on niks3 and both architecture `cache-root` outputs. For each root it pushes, then creates `nix-homelab-main-<system>`. Pin creation refuses an absent root. A failed push stops the effect; it must not produce a success status for an unreconciled pin.

Both commands use `--auth-token-script "nixbot-id-token https://cache.shrublab.xyz --json"`. The pinned client's pins help text omits this supported flag; a parser/token-resolution probe confirmed support. No temporary token file or static effect credential is needed.

The cache's nixbot provider binds:

| Field | Configured expectation; real-token preflight still required |
| --- | --- |
| Issuer | `https://nixbot.shrublab.xyz` |
| Audience | `https://cache.shrublab.xyz` |
| Repository | `Shrub24/nix-homelab` |
| Ref | `refs/heads/main` |
| Event | `push` |
| Effect | `default.cache-retain` (qualified name in the pinned source) |
| Scope / pins | `write` / `nix-homelab-main-*` |

PR tokens have no main ref, and another effect must not match. These source/configuration expectations and local claim fixtures are **not** real-token rejection evidence. Preserve other repositories' cache grants. Homelab's old GitHub build/pin grants stay during cutover and are removed only at its final stage.

### Activation order and token preflight

Before deploying cache trust, obtain a real issued token, verify its signature against the issuer's actual JWKS, and record only sanitized issuer/audience/subject/repository/ref/event/effect values. Never paste the JWT, helper response, signing key or bearer credential into logs or this repository. `nixbot-id-token` requires an authorized effect context; it is not a general interactive token mint.

**Bootstrap prerequisite remains open:** this disabled coordinator cannot yet issue that evidence. If no already-running issuer is available, agree a controlled issuer/bootstrap procedure with the operator before proceeding. Do not silently activate normal builds first, manufacture a token fixture and call it observed, or weaken the rule to get past the ordering requirement. Cache-host trust must be deployed before the first normal main reconciliation effect; the final coordinator activation follows that cache-host deployment.

After the preflight:

1. Stage tracked changes and run local gates. Review the enabling tree, recipients, placement expectations and exact Cloudflare plan; apply no unrelated pending resources.
2. Authorize the separate builder key and deploy the cache host with the verified scoped rule through existing deployment tooling. Preserve old grants while both paths coexist.
3. Enable/activate home-forge and publish only the reviewed route. The application listens at `127.0.0.1:8010`; Tailscale Serve fronts it on the private address at the same port using TLS. Verify OAuth, webhook signatures and listener isolation before enabling the discovered project.
4. The unit waits for the shared PostgreSQL setup/provisioning units. The substrate owns the peer role, database and export; upstream owns schema migration. No independent local database is enabled.
5. Observe PR, fork approval, merge reuse, publication, pins and recovery before changing required checks or deleting old CI authority.

## Acceptance and evidence

Record the source revision, build/effect IDs, timestamps, commands and sanitized outcomes. A cached ARM output is not proof of remote execution. A local mocked failure is not a live outage experiment.

- PR: both architecture checks build. Retain ARM builder-side `nix-daemon` accepted-connection evidence and `/nix/var/log/nix/drvs` build logs. Prove clean-store substitution with local builds disabled.
- Admission/authentication: an untrusted fork waits for Approve CI and builds after approval. Anonymous/unauthorized controls and spoofed headers fail. Malformed webhook signatures enqueue nothing; signed deliveries reach the service without an interactive gate.
- Main: an owner-approved merge of an up-to-date equal-tree PR reuses its build, then runs reconciliation and moves both pins to the new cache roots. Equal-tree local derivations are only a prerequisite to this observation.
- Cache repair: coordinate a cache outage, restart `default.cache-retain` from its main build, and record visible failure. Recover niks3 and restart that effect again; verify fresh publication and both pin targets. No `when.changed` guard skips an unchanged restart.
- Token rejection: test actual PR and other-effect tokens against the cache, recording refusal without exposing bearer values. Contrast with the accepted main reconciliation identity; configuration matching alone is insufficient.
- Downtime: coordinate stopping nixbot, pushing and restarting it. Record the delivery result, which work was discovered and which was lost, then demonstrate a rerun or subsequent push recovery. Do not assume missed webhooks are replayed.

### Observation register

| Experiment | Expected from source/configuration | Observed result |
| --- | --- | --- |
| Cache stopped, effect restarted | Effect fails; no misleading pin success | **Pending — not executed** |
| Cache recovered, effect restarted | Both roots pushed and pins repaired | **Pending — not executed** |
| PR / other-effect token | Scoped provider refuses it | **Pending — no real token tested** |
| Stop / push / restart | Lost webhook is not assumed replayed; rerun/next push repairs | **Pending — not executed** |
| ARM build and clean-store substitution | Remote execution plus complete availability | **Pending — not executed by nixbot** |
| PR/main reuse and rolling pins | Reused build; main effect moves both pins | **Pending — not executed** |

Replace pending cells with actual evidence, including contradictions, not restatements of the expected column. Coordinate outages before running them; they affect other fleet clients.

## Required checks, merging and retirement

Only after the observed cutover, set main's ruleset to require `nixbot/nix-eval` and `nixbot/nix-build` from the actual nixbot App integration ID and require up-to-date branches. Repository admins retain bypass. Enable GitHub auto-merge and platform auto-merge for the selected Renovate classes. A red check must block an ordinary merge; human PRs must wait for the operator. The owner supplies nix-fleet's future producer auto-merge input; until that supported input lands, producer PRs may need manual merge. This change edits no nix-fleet files.

`ci.yml`, `pipeline.yml`, `promote.yml`, `accept.yml`, `candidate-sweep.yml`, `fleet-build.yml`, `verify-cache.yml` and `package-updates-refresh.yml` are already deleted: nixbot validates, builds, reconciles the cache and produces the update pull request from its schedules, and Actions keeps only validation (`ci.yml`) and deployment (`deploy.yml`, `deploy-host.yml`). Remove the update-candidate, accept-update and obsolete lifecycle variables in the repository settings, and check every retained caller before removing a CI secret. Keep all credentials `deploy.yml` and `deploy-host.yml` still use, including their Tailscale access, and keep other repositories' cache rules. Historical decision entries remain historical.

**No deploy effect, deploy-tag rule, deploy credential or deployment acceptance test belongs here.** Cache reconciliation changes artefact availability, not running hosts.

## State, maintenance and rollback

Upstream owns `/var/lib/nixbot` (`0700`); PostgreSQL owns projects, sessions and jobs. The substrate exports the database before restic; state-directory backup is live, not an atomic snapshot with the database. Clones/logs may need rebuilding. Restore database export and state in isolation, with webhook delivery/scheduling disabled, then restore ownership/private modes and explicitly choose incomplete jobs to rerun. Credentials come from the operator-managed encrypted file.

Before maintenance, pause/disable the project. Until retirement, keep the current CI usable. After retirement, an operator-approved rollback must restore a coherent required-check/workflow configuration before disabling the only CI; do not strand merges on absent checks. Disable deliveries, cancel/drain work, then revert the gate/route through the retained deployment tooling. Preserve database/state and coordinate shared-token revocation if retiring after compromise. The separate builder-key removal must not remove other coordinators' authorization.

## Local validation

```sh
nix build --no-link .#checks.x86_64-linux.nixbot-contract .#checks.x86_64-linux.cache-retain
nix build --no-link .#checks.x86_64-linux.nixbot-package
nix flake check --no-build --all-systems --option allow-import-from-derivation false
just checks all
nix build --no-link .#checks.x86_64-linux.treefmt
openspec validate deploy-nixbot --strict
```

The selected-module fixture uses synthetic credentials to validate real configuration and named failures, not to authenticate. The cache-effect check runs the real script with a stubbed external client to verify failure propagation, order and unchanged restart, plus evaluated trust constraints. The mutation-heavy shell contracts are not a `checks` member; `just checks all` and the `repo` job run them through `scripts/run-repository-contracts.sh`. None establishes live login, signed-token acceptance, remote nixbot execution, production publication or cutover.
