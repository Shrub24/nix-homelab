# Proposal

## Why

Deploy a personal location-history service on OCI without introducing a container-only build or a second database mechanism. **Core value:** reproducible native packaging with authenticated device ingestion and recoverable location history.

## What Changes

- Package GeoPulse v1.39.1 (`77e9c0eb`) as a Java 25/Quarkus JVM backend and a static frontend, with offline dependency hashes and a small PKCE patch. Native-image compilation and an upstream flake contribution are follow-ups, not prerequisites.
- Publish a discovered `geopulse` aspect selected only on `oci-melb-1`, backed by a dedicated PostgreSQL consumer with PostGIS and `postgis_topology` provisioned by the existing substrate.
- Publish `geopulse.shrublab.xyz` through the existing edge with no Cloudflare Access gate. Browser sessions use Kanidm; device sources retain their own application credentials. Bootstrap stays private until the owner account and registration restrictions are verified.
- Keep Kanidm PKCE enforcement enabled by patching the application. Grant `openid profile email` to `users` only; enable RS256 compatibility for this client because its verifier is RSA-only.
- Preserve the database-managed OIDC provider and registration policy as explicit operator setup, rather than claim environment variables declare them.
- Deliver signing and encryption keys through SOPS, register backup/recovery, and add the packages to the existing package-update mechanism.
- Publish builds through the existing fleet cache under the owner's accepted interpretation of the personal-use BSL grant; retain the license in package outputs.

Constraints: ARM64 is the deployment target; no agent-generated secret material, no public first-user race, no PostgreSQL superuser grant to the application, and no AI, MQTT or multi-user bearer ingestion in this first deployment.

## Capabilities

### New Capabilities

- `geopulse-service`: native deployment, owner bootstrap, browser identity, device ingestion and recovery of personal location history.

### Modified Capabilities

None. Reuse `provider-owned-oidc-uris` and `policy-service-catalog`. The legacy `postgres-shared-access` spec describes superseded LiteLLM options; implementation must follow the current declaration-only consumer registry, not recreate those options.

## Impact

New package definitions under `pkgs/geopulse/`, an aspect under `modules/apps/`, package publication/update registrations, OCI placement, web and identity policy, host-scoped client-secret binding, service-scoped keys/credentials, backup registration and operator documentation. No Homelable deployment is included: its mutable topology is not a projection of the declarative inventory.

Evidence: `docs/research/geopulse-deployment.md` and `docs/research/geopulse-inbox-zero.md`. Offline builds, PKCE patch behaviour, PostGIS compatibility and real device/login acceptance remain implementation gates.
