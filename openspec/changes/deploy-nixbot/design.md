# Design

> NB-1 through NB-7 and the original migration plan below record the pilot baseline. NB-8 through NB-12 supersede its CI-authority, memory, publication and cutover decisions. Deployment remains outside nixbot; no deploy effect, tag rule or deploy credential is introduced.

## Context

See proposal.md for motivation and scope. `modules/flake/builder-access.nix` projects known hosts and SSH configuration from nix-fleet's canonical inventory; it deliberately configures no scheduling. `modules/flake/build-account.nix` authorizes only `config.fleet.ci.sshPublicKey`. Consequently, deploying a coordinator does not by itself grant remote builder access.

`modules/cache/niks3-cache.nix` currently federates GitHub Actions identities, bound to reusable workflows and repository-specific pin namespaces. Those credentials do not apply to a persistent service. `pipeline.yml` calls nix-fleet's v3 candidate pipeline; nixbot checks are not a substitute for `update-candidate`.

Upstream was inspected at `Mic92/nixbot@d020013fa0db4ec40ddd0593b9bfce65fedbff64`. Its module exposes GitHub OAuth, generic OIDC, socket activation, PostgreSQL configuration, streaming uploaders and outside-contributor approval. Source references:

- [NixOS module](https://github.com/Mic92/nixbot/blob/d020013fa0db4ec40ddd0593b9bfce65fedbff64/nixosModules/nixbot.nix)
- [GitHub setup](https://github.com/Mic92/nixbot/blob/d020013fa0db4ec40ddd0593b9bfce65fedbff64/docs/GITHUB.md)
- [OIDC and permissions](https://github.com/Mic92/nixbot/blob/d020013fa0db4ec40ddd0593b9bfce65fedbff64/docs/OIDC.md)
- [OAuth implementation](https://github.com/Mic92/nixbot/blob/d020013fa0db4ec40ddd0593b9bfce65fedbff64/nixbot/nixbot/auth.py)

The OpenSpec configuration still describes retired import filters and transport contracts. Follow the current discovered-aspect model and resolved web catalog instead. The existing build-plane spec also forbids automatic PR builds; its delta explicitly introduces this bounded exception rather than treating the deployment as conforming already.

## Goals / Non-Goals

**Goals:** One working coordinator on home-forge, GitHub-authenticated control, both fleet architectures, independently observable niks3 publication, recoverable state, and a rollback that leaves current CI intact.

**Non-Goals:** Replacing update production, candidate acceptance, cache pinning or deployment; enabling other repositories automatically; effects execution; Kanidm integration; proxy-header authentication; a new builder inventory or custom CI engine.

## Decisions

### NB-1: Consume the upstream module; place one coordinator

Publish `flake.modules.nixos.nixbot` from `modules/ci/nixbot.nix`, importing the pinned upstream NixOS module and supplying fleet policy only. Selection enables the service. Declare the input in the tree and regenerate `flake.nix`; verify all host evaluations remain IFD-free. Do not blindly force upstream's package dependencies to follow our baseline without verifying compatibility.

Preserve upstream's `/var/lib/nixbot` state directory and `0700` permissions rather than rewriting its hardcoded working directory and runtime assumptions. Bound concurrency and evaluation memory for home-forge; begin with two evaluation workers at 2048 MiB each and at most two concurrent attribute builds, adjusting only after observing resource use. These limits do not cap every process or the total Nix daemon memory; verify total impact during acceptance.

### NB-2: Native GitHub login; one public hostname

Use `nixbot.shrublab.xyz` for the UI, OAuth callback `/auth/github/callback`, and `/webhooks/github`. Set Cloudflare Access off for the entire hostname, preserve authenticated origin pulls, and use GitHub App signature verification for webhooks. Application authorization, not a partially protected edge, is the boundary. Anonymous users may read public projects; they may neither control builds nor inspect private projects.

Keep `allowUnauthenticatedControl = false`, `proxyAuthHeader = null` and OIDC disabled. Configure an explicit provider-qualified administrator, and rely on GitHub repository permissions for ordinary users. The operator supplies their GitHub login at bootstrap; there is no default wildcard administrator.

Kanidm is deferred by owner choice. It would need explicit OIDC admin/viewer mappings, and the inspected OAuth flow supplies no PKCE challenge or verifier. Enabling it now would require a client-specific `allowInsecureClientDisablePkce` exception. Prefer GitHub login over that exception; retain Kanidm's enforcement and revisit when upstream supports PKCE. No Kanidm client or secret is added by this change.

Use the current Caddy ingress and policy-derived endpoint, not a second nginx ingress. Upstream permits `nginx.enable = false` and `useHTTPS = true`; its socket then listens on the configured TCP port. Bind the socket to loopback with a targeted socket override, and use the existing provider-side private TLS front (`tailscale-serve`) so the edge reaches home-forge without a public backend port. Verify the effective listener and front rather than assuming that disabling nginx implies loopback binding. The backend and front share the policy port but bind different addresses: loopback and the tailnet address respectively. Check for collisions on those addresses.

### NB-3: Separate GitHub App and bounded build admission

Create a nixbot GitHub App installed only on `Shrub24/nix-homelab`, with read-only contents/metadata/pull-request access and check reporting permissions described upstream. Keep contents and pull-request write permissions off: there are no effects. Enable outside-contributor approval; use a strict trusted-association list (OWNER, MEMBER, COLLABORATOR), not upstream's broader CONTRIBUTOR default. Repository allowlisting is explicit in service configuration as well as App installation.

Do not configure effects secrets, writable mountables, arbitrary event effects or deployment keys. Built flake outputs are untrusted sandboxed work; service credentials must not be supplied to those builds. Enable the project only after configuration, authorization and resource checks pass.

### NB-4: Derive scheduling and authorize the coordinator locally

Reuse nix-fleet's pure builder-profile projections to derive architecture, endpoints, SSH host keys and capacity. Give nixbot a separate SSH key, not the GitHub Actions coordinator key. By owner direction, keep authorization in homelab: `modules/ci/nixbot-build-account.nix` contributes to the local `build-account` aspect and adds the public key on every host of the canonical `ci` profile. Preserve the existing Actions key, keep the current fleet pin, and make no nix-fleet edits. This is consumer-owned authorization, not a second inventory.

Scheduling is scoped to the coordinator. Existing hosts must not gain `nix.buildMachines` merely by selecting `builder-access`. A successful x86 build on home-forge alone does not demonstrate ARM dispatch: acceptance requires a new ARM build and evidence of its remote execution. Keep SSH keys available to the dispatching Nix daemon under its actual execution model, not merely to an interactive nixbot shell; retain host-key verification.

### NB-5: Stream to niks3; keep publication distinct from build success

Use `services.nixbot.uploaders` with `pathsVia = "stream"` and the pinned niks3 client's `push --stdin` protocol. Upstream explicitly documents this combination. It queues local intermediate paths plus attribute outputs, and persists pending work across restarts. This supersedes the preliminary assumption that a custom post-build hook was needed.

Use upstream's native `services.nixbot.niks3` integration, resolving the write endpoint from the existing private catalog. The owner explicitly accepted the existing static admin API-token model after inspection of niks3 `server/auth.go` at `27d6bdbf`: static tokens receive read, write and admin scopes. Deliver the existing token through a service-scoped SOPS field and systemd credential; a separate file does not confer independent scope or revocation. The credential can move pins even though nixbot is not configured to do so. Do not reuse GitHub Actions OIDC identities, R2 credentials or deployment secrets. Scoped short-lived federation is deferred.

Uploader failures are logged and do not fail nixbot builds upstream. Preserve that distinction: expose publication errors to operators and prove substitutability independently. Neither a green nixbot check nor successful queuing authorizes the workflow to move a main pin or accept a candidate. The accepted static credential nevertheless has pin authority; this is a security ceiling, not an enforced denial. No claim is made that the stream captures every intermediate built on remote machines; acceptance covers the complete referenced output closures needed by consumers.

### NB-6: Existing PostgreSQL and backup contracts

Disable upstream's independent local database provisioning. Register nixbot as a peer-authenticated consumer of home-forge's `forge` cluster through `modules/database/postgres/_consumer.nix`; supply the corresponding Unix-socket database URL via upstream's external-database option. Tie startup to completion of provisioning, not just the database process.

The PostgreSQL mechanism owns consistent exports. Register service-owned state with state-backups without a raw live database copy; retain state required for repository enablement, sessions and queue recovery, and document which clones/logs can be rebuilt. Preserve private-state permissions in staging and restore. Register failures through `services.notify.events` and use existing journald/telemetry rather than a second log pipeline.

### NB-7: Trial without changing promotion authority

Keep current validation and build workflow callers. New nixbot checks are informative, not required merge checks during the trial. `update-candidate` remains the candidate gate; never require `update-accepted`. There is no second update producer, no main pin writer and no automatic deploy effect.

## Risks / Trade-offs

- Public-project logs are readable without login → explicitly accept this behavior; exclude secrets from build environments and do not treat logs as confidential storage.
- An evaluator or build can exhaust coordinator capacity → explicit admission, conservative concurrency, resource observation, outside-contributor approval and cancellation testing.
- A daemon cannot access a user-owned SSH credential → prove daemon-level dispatch on both architectures before enabling the project.
- An uploader is unhealthy while checks are green → independent publication monitoring and clean-store substitution tests; no promotion authority.
- Co-located CI increases risk to home-forge workloads → no effects secrets or deployment access, retain upstream hardening, keep the listener private, and preserve an immediate disable path. Nix sandboxing is not a claim of protection against all kernel/daemon vulnerabilities.
- Package and auth behavior can move on a branch → pin the source and record acceptance against that revision.

## Migration Plan

1. Add the local coordinator authorization contributor, service, routing, database and secret contracts with focused evaluated checks. Selection is enablement: `policy/nixbot.nix` carries only the operator's GitHub App values and the builder public key, and evaluation fails until those are real; do not edit nix-fleet.
2. Operator creates the GitHub App, the dedicated builder key and the existing admin cache credential, prepares encrypted service/OAuth secrets and confirms the service recipient policy. Agents do not create, decrypt or edit encrypted payloads.
3. Activate home-forge and provision the database. Publish only the approved route/DNS changes after reviewing the exact plan. Install the App only for the allowlisted repository; verify OAuth login and negative authorization before enabling builds.
4. Exercise PR/default-branch events, outside-contributor approval, both architectures, uploader recovery, clean-store substitution and database/state restore. Record evidence in the runbook without credentials.
5. Roll back by disabling the project and App webhook, cancelling/draining work, and reverting the aspect selection/route as appropriate. Preserve database and state for recovery; revoke the service credentials if retiring it. Existing CI remains usable throughout.

## Superseding CI/cache decisions

### NB-8: Admission plus complete checks replaces the candidate lifecycle

Supersedes NB-7's informative-only trial and the Actions candidate/build authority described in D-110. Nixbot becomes the sole CI for `Shrub24/nix-homelab` after observed cutover. GitHub merges: automation PRs may auto-merge on green; human PRs wait for the operator. Main's ruleset requires `nixbot/nix-eval` and `nixbot/nix-build` from the nixbot App integration and requires up-to-date branches, with repository-admin bypass. No effects or event status becomes a merge gate.

Remove `github.userAllowlist`: upstream ORs owner and repository grants, so granting `Shrub24` admits every discovered repository it owns. Exercise the effective admission behavior against the allowed repository, another owner repository and a foreign repository. Stock PR approval is sufficient on this personal repository: in-repository branches build; untrusted forks wait for Approve CI. No admission patch is included. Use two evaluation workers at 3072 MiB, superseding NB-1's 2048 MiB setting. Retain a concise comment on the peer-only PostgreSQL provisioning workaround rather than expanding the database mechanism in this change.

All validation must be buildable through `checks`, not a parallel Actions job. Preserve the existing shell contracts, including their copied-tree negative probes, in an isolated NixOS test with its own writable store and source checkout; this avoids granting recursive access to the coordinator daemon or rewriting the tests as source-presence assertions. Run the same suite locally through its shared runner. Keep treefmt, generated-flake freshness, dependency freshness, host toplevels, packages/cache-root and the selected-module contract in checks. Configure nixbot evaluation with IFD disabled.

### NB-9: Main reconciles artefact availability and retention

Supersedes NB-5/NB-7's no-main-pin-writer policy; the static uploader token's accepted admin scope is unchanged. Publish `herculesCI` using nixbot's pinned effects library. `onPush.default.outputs.effects.cache-retain` exists only for main, with `lock = "cache"`, `idTokenAudiences = [ "https://cache.shrublab.xyz" ]` and an explicit empty `secretsMap`. Both architecture cache roots and niks3 are inputs. Push each root, then create `nix-homelab-main-<system>` pointing at it; a cache miss or failed push must fail the effect. No `when.changed`: restart always reruns reconciliation and is the repair path. This manages build artefacts, not host activation.

Use `niks3 --auth-token-script` with `nixbot-id-token <audience> --json`. Add one nixbot provider beside existing cache federation, bound to issuer, audience, repository, main ref, push event and the exact cache effect identifier; grant write and only `nix-homelab-main-*` pins. The inspected source uses qualified identifiers such as `default.cache-retain`. Capture an actual issued token and verify its sanitized claim values before deploying cache trust; source inspection is not that observation. PR identities have no main ref and another effect must fail the rule. Keep the old homelab GitHub grants during cutover, removing them only at the final retirement stage; other repositories' grants stay.

### NB-10: Equal source trees produce reusable outputs

Supersedes the revision-stamping portion of D-057, not its tracked-source boundary. Remove `system.configurationRevision = self.rev or self.dirtyRev or null`; retain `environment.etc."nixos-source".source = self.outPath`. A merge commit must not change a host derivation solely through its commit ID. Verify equal-tree outputs independently and observe nixbot's PR/main reuse; neither observation substitutes for the other.

### NB-11: Deployment remains separate

No deploy effect, deploy tag trigger/ruleset, deploy credential in nixbot, deploy acceptance test or deployment-tool deletion is part of this change. Keep `deploy.yml`, `deploy-host.yml`, deploy-rs/operator tooling and the credentials they still reference. Main cache reconciliation does not activate hosts. Keep `effects_on_pull_requests = false`, no extra effects branches, no `onEvent` effects and no per-repository effects secrets. Every `mkEffect` explicitly declares its empty secrets map.

### NB-12: Observed cutover precedes retirement

Follow these stages within this change: (1) fixes, checks and cache effect; (2) operator credentials, real-token shape verification, cache-host trust deployment before the first main effect, then coordinator activation; (3) an observed PR, green merge, reused build, published roots and moved pins, plus failure/restart, negative-token and downtime experiments; (4) App-sourced main checks and GitHub auto-merge policy; (5) CI/candidate retirement. Merge remains owner-approved.

Retire `ci.yml`, `pipeline.yml`, `promote.yml`, `accept.yml`, `candidate-sweep.yml`, `fleet-build.yml` and `verify-cache.yml` only after these gates. Remove update-candidate, accept-update and the obsolete lifecycle variables. Remove a CI secret only after exhaustive reference checking; deployment's Tailscale credentials remain. Keep the scheduled package-update producer, its automation environment and App key. The owner supplies nix-fleet's future producer auto-merge input; do not edit upstream or pass an unsupported input in advance. Until that lands, its PRs may require manual merge. Enable Renovate platform auto-merge for explicitly selected dependency classes.

Accepted risks: the uploader retains the static admin token and could move pins despite the normal scoped effect path; lost webhooks are not replayed during downtime and require rerun/next push; admitted PR builds share home-forge with the controller, with the sandbox as their boundary. No deploy authority is added. Record actual cache outage/restart, negative-token and downtime results separately from expectations in the runbook. Do not fill those results from source inspection.
