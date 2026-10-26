# Design

## Context

See `proposal.md` for motivation. The R2 bucket `shrublab-assets` and public custom domain already exist. The shared bucket-scoped key is in `secrets/common.yaml` under `assets`; the R2 endpoint is the fleet's existing `policy/globals.nix` S3 endpoint. Brand URLs already address `shrublab/` objects.

## Goals / Non-Goals

Deliver all twelve routed application icons and the two consumed vector brand assets through one publisher, following operator acceptance of the three-app pilot. Leave manually uploaded wallpaper and R2 infrastructure ownership unchanged. No automatic pruning, generic asset discovery, raster conversion, timer or build-time network fetch.

## Decisions

### AS-1: Source policy is central; runtime attachment belongs to the service

`policy/assets.nix` declares source choices, bucket and public address. A source is a tracked file, local service path, or explicit HTTPS URL. Service modules register local listeners, ordering units and image/package restart triggers through `modules/assets/_registration.nix`; the publisher names no service. The declaration-only contract evaluates without selecting the mechanism, following state-backups' existing consumer pattern. Authentik reads the central icon policy, not another host's NixOS evaluation, to identify managed keys.

Curated SVGs are tracked under `assets/` with upstream revision and license attribution. Local paths follow installed application artwork. External URLs are fetched at runtime, preferably commit-pinned; they do not provide fixed-output verification. Vendor exact bytes when that guarantee matters, rather than introducing one fetch hash and updater per icon.

### AS-2: One concrete unit per registration

All inputs are known during evaluation, so generate `assets-update-<name>.service` rather than a template and runtime registry lookup. Each oneshot remains active after success, has source/configuration/service restart triggers, and orders after its owning unit where applicable. Local fetches use the listener supplied by the service, not a catalog endpoint that may be a TLS front. External and file sources need no application readiness wait.

An operator refresh command restarts the generated unit list; starting an already-active target is not a refresh. Startup and activation request the units through an aggregate target. Each unit has a bounded fetch window and no automatic restart loop; a failure affects only that object and an explicit restart can retry it.

### AS-3: Preserve last-good content

Read and validate the entire candidate before writing. Recognize supported image formats from their bytes, not an HTTP success status or filename; HTML login/error responses must never replace an image. Set the uploaded Content-Type explicitly. Compare content SHA-256 stored as object metadata plus Content-Type and cache policy. A missing object is uploaded; an unchanged object causes no write; errors other than object-not-found fail closed. Publication never deletes objects. No fallback is written over an existing successful publication.

A shared bucket makes host-local pruning unsafe: one host's registry omits other hosts' assets. Defer pruning entirely and document explicit object removal. `icons/` holds application icons; `shrublab/` holds brand assets. The wallpaper is manually managed and not reconstructed by this change.

### AS-4: Existing credentials, explicit capability selection

Select `assets-publisher` on all three application hosts. The mechanism owns SOPS registrations and a credential environment file referencing the existing `assets/access_key_id` and `assets/secret_access_key` in common.yaml. Secrets do not enter the Nix store. Its shared authority is one public-content bucket, not account or bucket administration; per-host keys would not narrow object authority.

### AS-5: Stable public addressing

Application objects use `icons/<client-key>` with explicit type metadata. Authentik uses these keys for all twelve routed applications. The external Cloudflare federation client has no launch route and no publisher. Termix's module registers its source when selected; it is currently undeployed. Logo and favicon keep their existing distinct URLs under `shrublab/`. Only source owners write objects; no publisher mutates Authentik fields. Rollback can restore previous dashboard URLs independently of publication.

## Risks / Trade-offs

- Local service not ready: bounded retries, then failure without writes. Ordering alone does not establish liveness.
- Incorrect source or login response: inspect candidate bytes before upload.
- Shared credential leak: limit token scope to this bucket and public assets only.
- Operator edits a managed key: the next publish restores declared bytes; manual wallpaper is outside the managed set.
- Stable keys cache old content: use a short explicit browser cache lifetime rather than immutable caching.
- Missing first publication: deploy publishers before checking the dashboard; live object acceptance remains an operator gate.

## Migration Plan

1. Land central policy and reviewed SVGs.
2. Land publisher, isolated behavioral checks and operator documentation.
3. Register all application sources and the two brand files; select the mechanism on their hosts and switch dashboard URLs.
4. Run focused checks and repository gates before deployment.
5. Deploy oci-melb-1 and home-forge, then la-admin-1; verify published content types, unchanged no-ops and unauthenticated dashboard images. Do not upload or change live infrastructure during implementation.

Rollback: restore previous dashboard icon URLs and deselect the publisher. Objects remain in R2; removal is explicit and never inferred from a partial host registry.
