# Proposal

## Why

Add a self-hosted fitness and nutrition application at `https://fit.shrublab.xyz`, with Authentik sign-in and recoverable state managed by the fleet rather than a separate Compose installation.

**Core Value:** Operate SparkyFitness as one ordinary fleet application: reproducible runtime, explicit access, scoped secrets and a recovery path that preserves health records and uploads.

## What Changes

- Add a host-selected `sparkyfitness` aspect on `oci-melb-1`, running the official frontend and backend OCI images. Keep the frontend image's nginx for application asset serving and routing; the existing Caddy edge remains the sole public ingress.
- Use the existing native PostgreSQL cluster. Extend its consumer contract narrowly to provision a database owner's additional login roles without transferring database ownership or giving the application cluster-wide role-management privileges.
- Publish `fit.shrublab.xyz` with application-native Authentik SSO and no Cloudflare Access gate. Register a canonical OIDC client, including an explicit administrator-group mapping. Keep local password login off normally and document a retained local administrator's break-glass path.
- Persist application files under `/srv/data/sparkyfitness`, register backups alongside the substrate's database export, and document a joint restore procedure.
- Add service-scoped secret scaffolding, image pins, failure notifications and operator acceptance steps. Secret creation and live deployment remain operator-controlled.

### Key constraints

- Initial host: `oci-melb-1` (`aarch64-linux`); select release images available for both ARM64 and AMD64.
- Preserve the official frontend/backend topology, not the Compose database container. No upstream Nix input or local application derivation.
- Core application only: no Garmin microservice, AI-provider integration or additional fitness-provider provisioning.
- Aspect selection is enablement. No bootstrap/private/publish lifecycle switches; expose actual application settings for host overrides.
- Service-scoped secrets default in the owning module. Their SOPS rule grants only the owner and `oci-melb-1`, which also runs Authentik.
- Tests cover database isolation and repo-owned integration behaviour, not image literals, port values, option assignments or Nix's own checks.

## Capabilities

### New Capabilities

- `sparkyfitness-service`: application placement, browser/API exposure, sign-in, persistence and recovery.

### Modified Capabilities

- `postgres-shared-access`: provision additional password login roles for one consumer database while preserving its single owner and per-role access boundaries.

## Impact

- Add `modules/apps/sparkyfitness.nix`; select it in `modules/hosts/oci-melb-1/default.nix`.
- Extend `modules/database/postgres/_consumer.nix` and `modules/database/postgres.nix` through the existing declaration-only contract, not a SparkyFitness-specific substrate branch.
- Update `policy/{oci-images,web-services,identity,assets}.nix`, `modules/identity/_secret-sources.nix`, `.sops.yaml` and `secrets/.templates/services/`.
- Add focused database integration coverage, subsystem documentation and an operator runbook. Reuse existing catalog, ingress, identity, container-address and backup checks.
- Related specifications: `openspec/specs/postgres-shared-access/spec.md`, `provider-owned-oidc-uris/spec.md`, `karakeep-service/spec.md`, `state-backups/spec.md` and `policy-service-catalog/spec.md`. The first two retain historical LiteLLM/Kanidm wording; this change adds the required database behaviour without reviving those implementations or rewriting the unrelated identity migration.
- No breaking change to existing consumers: additional database roles default to an empty set.
