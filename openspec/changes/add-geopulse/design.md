# Design

## Context

See proposal.md for motivation. GeoPulse v1.39.1 combines a Java 25 Quarkus backend, Vue static frontend and PostgreSQL. It applies Flyway migrations at startup. Native dependency hashes and ARM execution are not proven. The repository already provides consumer-owned PostgreSQL registration, SOPS delivery, the intrinsic OIDC contract, Caddy ingress and a package-update batch.

Upstream OIDC providers and registration switches are database-owned. The environment cannot declare a provider or reliably override a saved registration setting. Research is recorded in `docs/research/geopulse-deployment.md`; its missing-PKCE client exception is superseded by the owner's decision to patch PKCE.

## Goals / Non-Goals

**Goals:** native ARM deployment, owner-only authentication, authenticated location capture, recoverable encryption state and coherent package updates.

**Non-goals:** GraalVM native image, Docker fallback, automatic provider provisioning, public bootstrap, AI/MQTT, shared links, multiple ingest users, or Homelable deployment. An upstream package/flake contribution follows a working local build.

## Decisions

### GP-1: Package the JVM and static frontend together as one release

Use `pkgs/geopulse/` with backend and frontend derivations sharing a single source pin. Preserve Quarkus fast-jar layout, build frontend assets offline and install the license. Resolve Maven and npm fixed-output hashes during implementation, with JDK 25 and a Node version supported by the pinned frontend. Register one coupled updater through `modules/flake/package-updates.nix`, avoiding independent version writers. Publish both architectures only after their builds pass; ARM is the deployment gate, not inferred from an x86 build.

The owner accepts publication to the existing fleet cache under the personal-use BSL interpretation. This records a deployment choice, not a legal assurance. Declare BUSL-1.1 on all three package outputs and use a GeoPulse-name-scoped unfree predicate at their package-instantiation seam; omitting license metadata would bypass rather than implement this policy. Native-image compilation adds risk without a current need.

Register the joined `geopulse` output as the coupled release owner, not `geopulse-backend`: the pinned updater limits writes to `pkgs/<registered-name>` and does not publish the documented custom write sets. Both halves remain derived from the same release. Revisit this registration if upstream publishes explicit write-set configuration; do not create a second writer merely for the frontend. The patch-applicability dry run uses the unpacked source tree returned by Nix prefetch; this is an implementation correction, not a new architecture decision.

### GP-2: Patch PKCE rather than weaken Kanidm

Maintain a narrow upstream-source patch that generates a fresh verifier per authorization attempt, sends its S256 challenge and persists the verifier with the short-lived login state. The exchange retrieves that verifier; state must be consumed once, without logging codes, secrets or verifiers. Preserve nonce, issuer, audience and expiry checks. If persistence needs a schema migration, add one forward-only migration compatible with Flyway rather than editing an applied migration.

Exercise authorization URL and token-exchange behaviour with an in-process fake provider, including failed and replayed callbacks; then verify against the fleet's actual Kanidm revision. The research used Kanidm 1.9.1 as reference material, not a replacement fleet pin. Keep PKCE enforcement enabled. Set `enableLegacyCrypto` for RSA token verification, with a `users`-only scope map. Provider subject remains the identity key; accounts require a primary email.

### GP-3: Native runtime and shared substrate

Publish `flake.modules.nixos.geopulse` under `modules/apps/`; OCI selects it and supplies only placement facts and secret paths. The backend runs under a dedicated user with loopback TCP access to PostgreSQL. Its consumer contributes PostGIS packages and extension setup; setup runs as the substrate administrator before application migrations. Do not grant superuser or extension-install privileges to the app. Verify the existing cluster major version and corresponding PostGIS compatibility before deployment; do not upgrade the whole cluster just to match compose.

Serve the static frontend on a GeoPulse-owned loopback Caddy listener with fixed upstream proxy mappings, using the existing Caddy runtime. The public edge route proxies to that frontend listener. Adapt upstream nginx semantics rather than adding nginx solely to copy a container layout. Preserve SPA callback fallback, `/api` and the fixed OSM tile proxy; do not create an arbitrary outbound proxy. Keep the backend loopback-only. Listener ports derive from web policy, with collision checks at implementation time. Runtime frontend configuration contains no secrets.

Use `/srv/data/geopulse/{backups,import,dumps}` for mutable files, preserving upstream runtime paths through explicit settings. SOPS owns RSA signing keys and the persistent AI-encryption key even though AI itself is unused: OIDC secrets depend on it. Verify key read access under the service sandbox; use systemd credentials where supported rather than making rendered-secret parent directories world-readable. Database and provider passwords never enter the store.

### GP-4: Private bootstrap precedes public activation

Keep a host-selected `services.geopulse.publicReady` fact false initially. The ingress projection must omit the public route in that state; merely refusing the backend health check is not isolation. Retain public identity metadata for callback construction without a live public route, using the existing policy resolver where possible and adding only the smallest GeoPulse-owned guard if necessary. Private access is through a loopback SSH tunnel; no public first-user window is allowed. For the real OIDC callback test, the operator must preserve the public HTTPS origin locally (temporary hostname resolution to a tunneled TLS listener with a valid certificate), not substitute a localhost callback or open the public route for bootstrap. Document and verify this tunnel procedure before deploying.

The operator creates the owner password account privately, records owner admin policy, creates the Kanidm provider through the admin interface using canonical contract values, and verifies account linking with auto-link left off. Set database-owned password and OIDC registration to closed, confirm owner login and recovery, then explicitly enable public exposure. Saved settings outrank environment defaults, so the runbook must verify actual settings. Public activation is an operator gate, not a claim that Nix validated the live database.

Use `geopulse.shrublab.xyz` without Cloudflare Access. Device clients use Basic credentials for a first OwnTracks/GPSLogger acceptance test. Opaque-bearer sources are deferred until their HTTP authentication path is proven; no multi-user bearer deployment because upstream lookup can misattribute duplicate tokens.

### GP-5: Reduce the public surface without breaking the UI

Deny public metrics and version diagnostics, MCP, sharing, home-content and unused ingest/AI paths. Evaluate whether the UI uses public geocoding and mobile-session endpoints before denying them; authenticated frontend behaviour must still work. Do not assume browser SSO protects an upstream `permit` route. Reuse the current ingress extension seam for ordered, route-scoped guards; do not introduce a generic access-policy framework.

### GP-6: Export-first recovery and upgrades

The substrate exports the database. Capture mutable import/backup files through the existing backup consumer contract; do not copy the live PostgreSQL directory. Operator-managed SOPS keys must survive recovery, especially the key that decrypts database-held OIDC credentials. Before an upgraded backend runs Flyway, take a verified database export. A Nix generation rollback alone cannot undo migrations; restore the matching export when rollback requires the old schema.

## Risks / Trade-offs

- Offline Maven/npm completeness → compute hashes and prove sandboxed builds before host selection.
- Patch maintenance → keep one release-coupled patch with regression tests and upstream contribution notes.
- Automatic database migration → explicit pre-upgrade export and tested scratch restore.
- Mutable provider/registration settings → one-time operator setup and live acceptance, not an environment-only claim.
- Public location API → source-specific credentials, negative authentication tests and single-user scope.
- External maps/geocoding/weather → document outbound dependencies and location privacy; no self-hosted geocoder added.
- JVM memory and PostGIS pressure → inspect startup/ingest resource use on OCI before accepting public operation.
- License conditions → retain the complete upstream license; owner's cache approval is not legal validation.

## Migration Plan

Build and test packages first. Prepare secrets as the operator, deploy privately, create and verify the owner/provider, close registration, test a device submission and an export/restore, then enable the public route and verify edge denials. Keep the previous generation and pre-migration export. Stop before public exposure if OIDC, PKCE, ingest attribution or registration closure fails.

## Open Questions

Implementation must establish fixed-output hashes, exact PostGIS compatibility, memory budget, and callback cookie behaviour. These are acceptance gates within the chosen approach, not grounds for silently substituting containers or disabling PKCE.
