# Design

## Context

See `proposal.md` for scope and the operator's placement/access choices. The repository already has the needed boundaries: app-owned aspect contributors, digest-pinned images, native PostgreSQL consumer registration, service-scoped secret defaults, canonical OIDC facts and state-backup contributions. GeoPulse is the closest runtime topology; Karakeep provides another dedicated-network example.

Research inspected SparkyFitness `main` at `2aa2e9bdeafd57b20a69fb100dccfc4e24e608c9` and release `v1.11.0` (`0d8525e88ea7b116a92cd3aa35f622f7682201e2`). Its Nix files and Docker nginx config are identical across those revisions. Both release images publish ARM64 and AMD64 manifests. No application build or live SparkyFitness acceptance has been performed.

The OpenSpec context and several base specs predate the current architecture: they mention filtered service roots, internal-contract modules, Kanidm and file-presence bootstrap gates. Current code, D-125/D-126 and the user's direction govern this design. The database delta adds behaviour to `postgres-shared-access`; it does not restore its historical LiteLLM implementation. Cleaning unrelated stale specifications is not part of this change.

## Goals / Non-Goals

**Goals:** preserve upstream application serving while integrating fleet-owned security, database lifecycle and recovery. Extend the database contract once for the concrete second-role consumer.

**Non-Goals:** a Compose runtime, an upstream Nix input, a generic application framework, a second public ingress, Garmin, AI setup, automatic secret editing, live deployment during implementation, or changes to other apps' authentication.

## Decisions

### SF-1 — Keep the official frontend/backend split

Publish a discovered `flake.modules.nixos.sparkyfitness` contributor under `modules/apps/`, with actual settings under `services.sparkyfitness`; selection deploys it. Use a dedicated Podman network, an unpublished backend and a frontend bound only to the loopback port declared by web policy. Its nginx serves assets and owns `/api`, `/health-data`, `/uploads`, `/mcp` and OAuth discovery routing. Caddy forwards the whole site and retains TLS/public-access ownership.

Initial images are `codewithcj/sparkyfitness:v1.11.0` and `codewithcj/sparkyfitness_server:v1.11.0`, pinned by manifest digest in `policy/oci-images.nix`. Research observed index digests `sha256:5eb77135ccd8e58492ee9bd19b8714ea4a73a99623b863a9287ccecb0557cd17` and `sha256:51a2d7c19bd99b50ea17e579fe8d9d4febed895595356b1ddafe0fa808caf75e`, respectively; verify registry metadata when landing the pins. Renovate owns subsequent updates.

The backend is a dependency of the frontend, so use the existing readiness helper with an explicit curl probe against its configured internal port and `/api/health`, plus a backend-owned finite start budget. The release Dockerfile installs curl and declares that endpoint. Confirm the binary and endpoint in the pinned image before enabling the probe; an image's own HEALTHCHECK is not sufficient for the deployed Podman's `sdnotify=healthy`. Do not add a probe to the leaf frontend merely for uniformity. Preserve a stop timeout longer than the application's graceful-shutdown budget.

**Alternative:** the native upstream module is maintained but community-supported and its nginx projection lacks the container's OAuth discovery routes. It would add source-build and proxy-parity ownership here. Revisit if native deployment gains parity and full build/runtime coverage.

### PG-1 — Extend the declaration-only consumer contract for the second role

The extension belongs in `modules/database/postgres/_consumer.nix`, as requested. Add `consumers.<name>.additionalRoles`, an attribute set keyed by login role name, defaulting to empty. Each additional role declares its password using the existing `{ file, key }` authority shape; it inherits the parent consumer's database and allowed source CIDRs. Do not add arbitrary privilege flags, role membership, separate database ownership or an application-specific provisioning branch.

`postgres.nix` renders role creation, LOGIN, password application and SCRAM access for these registrations. All of a consumer's roles and credentials exist before its `setupSQL` executes. Only the parent's owner role owns the database. Existing consumers retain their current behaviour. Additional roles do not duplicate database exports. Credential lifecycle hooks must cover the new roles as well as the owner.

SparkyFitness registers one database, a migration owner and a separate application login through this contract. Bridge traffic uses `host.services.internal`, its required host mapping, and the existing container-source CIDR. Resolve the cluster port from `services.postgres.localEndpoint`, not a copied host fact. The app and substrate read identical password keys from the service secret file.

Upstream supports pre-created roles: it authenticates as the application role before considering CREATE/ALTER ROLE. Keep both passwords explicit and converged so neither role needs CREATEROLE. Database-local schema permissions remain upstream migration responsibility; any required initial public-schema ownership/grant belongs in the consumer's existing `setupSQL`.

**Alternatives rejected:** importing upstream's local database initializer grants CREATEROLE; app-owned provisioning bypasses the consumer contract; two owner registrations for one database repeatedly transfer ownership. None is needed.

### AUTH-1 — One origin and one canonical client

Declare route `sparkyfitness` at `fit.shrublab.xyz`, provider `oci-melb-1`, direct loopback exposure, published posture, Cloudflare Access off and application OIDC on. Derive the application's public URL from its catalog entry with an ordinary override. Do not infer application settings from route posture.

Register the client in `policy/identity.nix` with the existing user/admin access convention and dashboard group `Everyday`. Use provider slug `authentik`; current Better Auth source and frontend wording identify `/api/auth/sso/callback/authentik` as its callback, not the stale OAuth guide's `oidc-callback`. Register that single route-derived callback and consume the canonical issuer/client facts through `_oidc.nix`.

Pass upstream's OIDC environment keys, auto-registration and administrator-group mapping. Do not set the global signup blockade: current source applies it to SSO user creation too. Disable ordinary password login and independent application passkey login by their actual upstream settings; Authentik owns interactive MFA. Expose the corresponding application environment/settings surface so a host can temporarily re-enable password login, not a `bootstrap` or `breakGlass` boolean.

Retain one local administrator credential in the service secret file, following `docs/identity.md`. Creating/verifying that account is an operator acceptance step using upstream-supported account/password management, not a database patch, data wipe or module lifecycle mode. Prove it works with Authentik unavailable before claiming break-glass acceptance; first-user admin promotion is not the authorization policy.

### SEC-1 — One service secret authority

Default the service's secret input to `secrets/services/sparkyfitness.yaml` using `mkSecretFileOptionWithDefault`. Scope its rule to owner and `oci-melb-1`. Include migration/app database passwords, API encryption key, Better Auth secret, `sparkyfitness/client_secret` and retained local administrator credentials. Bind the same client-secret source in `modules/identity/_secret-sources.nix` so Authentik and the app converge.

The module owns secret declarations, rendered environment, restart relationships and backup registration. No secret file is read for feature detection. The operator creates/edits encrypted secrets; implementation provides only the template and recipient rule. Never print credentials while testing registry or application access.

### DATA-1 — Separate database export from application files

Bind durable uploads and app-created backup files under `/srv/data/sparkyfitness`; make ownership agree with the pinned image's effective runtime identity rather than guessing from Compose's PUID variables. Temporary upload processing remains ephemeral. The substrate owns the PostgreSQL logical export. Register application files with explicit `live` consistency and exclusions for scratch data; do not back up the live PostgreSQL data directory or claim the app's own backup files replace the fleet export.

The encryption key is a restore input because integrations store encrypted data. The runbook restores roles, database and files into an isolated target at the recorded release, then verifies an existing fitness entry and an uploaded file. A live file capture plus logical database dump is not an atomic cross-resource snapshot; document in-flight upload limitations rather than claiming otherwise. This initial limitation is subject to the recovery acceptance below.

### VAL-1 — Test the joins we own

Add one focused PostgreSQL integration test using the real substrate provisioning/authentication path and an ephemeral cluster: authenticate as both roles, retain owner after repeated provisioning, reject unrelated-database access and role escalation, rotate only the application password and preserve data. Use synthetic credentials; do not test PostgreSQL's algorithm independently of our rendering.

Reuse existing catalog/identity/container-address/backup checks. Do not add a per-app list of literal images, ports, enables, health flags or obsolete-unit absences. Live application acceptance covers same-origin routing, SSO/admin versus ordinary-user access, retained local login and restore. Evaluation alone is not evidence of those behaviours.

## Risks / Trade-offs

- **External PostgreSQL is community-supported upstream** → follow its reduced-privilege path and prove startup/rotation with the pinned app before recording acceptance.
- **Role/credential ordering regression can affect shared-cluster startup** → keep the extension default-empty, test through the real provisioning path and evaluate all existing hosts.
- **Fresh SSO or administrator mapping differs from docs** → use current Better Auth source, verify both admin and ordinary identities, and retain an independently usable local administrator.
- **Wrong runtime UID, proxy forwarding or probe makes a healthy app fail** → inspect the pinned images, test through Caddy and use finite startup budgets. Do not infer acceptance from container process state.
- **Live files and database export can differ during writes** → document the limit and perform an isolated restore. If acceptance loses committed user data, resolve consistency before calling the change complete; do not add a new backup framework speculatively.
- **Schema migrations outlive deploy-rs rollback** → take a backup before upgrades; runtime rollback does not roll back PostgreSQL. Use version-matched restore if schemas are incompatible.

## Migration Plan

1. Implement on an anonymous change from current main; no new flake input or generated flake edit is required.
2. Land the consumer extension and runtime/policy wiring. Add only scaffolding for secrets, then pause for the operator to supply the encrypted file before host evaluation/activation requires it. There is no secretless generation or file-presence gate.
3. Run focused database validation and the parent-owned full gates on a stable, indexed tree. Verify the pinned ARM64 images and real probe.
4. Operator applies DNS policy as needed and deploys OCI after encrypted credentials exist. Confirm routing, first SSO login, claim-based admin access and retained local administrator; record acceptance, not merely a green deployment.
5. Complete a backup/isolated restore exercise. Other hosts need no deployment except if the shared-contract change is being independently rolled out there.
6. Roll back by returning the runtime configuration to its previous generation without deleting state. Before future image upgrades, record the release and database export; restore a matching export if the old release cannot read a migrated schema.

## Sources

- Upstream [Nix support disclaimer](https://codewithcj.github.io/SparkyFitness/install/nixos), [flake](https://github.com/CodeWithCJ/SparkyFitness/blob/v1.11.0/flake.nix) and [hash workflow](https://github.com/CodeWithCJ/SparkyFitness/blob/v1.11.0/.github/workflows/nix-update-hashes.yml).
- Release [Compose topology](https://github.com/CodeWithCJ/SparkyFitness/blob/v1.11.0/docker/docker-compose.prod.yml), [nginx routing](https://github.com/CodeWithCJ/SparkyFitness/blob/v1.11.0/docker/nginx.conf), [backend image](https://github.com/CodeWithCJ/SparkyFitness/blob/v1.11.0/docker/Dockerfile.backend).
- [External database setup](https://github.com/CodeWithCJ/SparkyFitness/blob/v1.11.0/docs/src/install/external-database.md), [role lifecycle](https://github.com/CodeWithCJ/SparkyFitness/blob/v1.11.0/SparkyFitnessServer/utils/dbMigrations.ts), [OIDC environment projection](https://github.com/CodeWithCJ/SparkyFitness/blob/v1.11.0/SparkyFitnessServer/utils/oidcEnvConfig.ts) and [Better Auth hooks](https://github.com/CodeWithCJ/SparkyFitness/blob/v1.11.0/SparkyFitnessServer/auth.ts).
