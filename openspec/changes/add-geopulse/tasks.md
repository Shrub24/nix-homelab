# Tasks

## 1. Native packages and PKCE (GP-1, GP-2)

- [ ] 1.1 (x86_64 implementation reviewed; Node 22 accepted; ARM64 build remains outstanding) Add coupled backend/frontend package definitions under `pkgs/geopulse/` from v1.39.1 with pinned source, Maven and npm hashes and installed license. Preserve fast-jar/runtime frontend assets; verify sandboxed builds on ARM64 and x86_64 without a Docker or GraalVM fallback, and document the build seam for an eventual upstream contribution.
- [ ] 1.2 (x86_64 patch build reviewed; six scratch tests and mutation check passed; patched ARM64 build remains outstanding) Add the narrow PKCE source patch and any forward-only state-schema migration. Land behavioural tests for per-attempt S256 challenges, the matching token-exchange verifier, missing/expired/replayed state and rejected wrong verifiers; run the focused upstream test suite and rebuild the patched ARM backend. Verify nonce/issuer/audience validation remains intact and no sensitive values are logged.
- [x] 1.3 Publish the packages through existing package aggregation and register one release-coupled updater in `modules/flake/package-updates.nix`. Verify cheap update checking returns the shared version and a scratch refresh updates both source/dependency pins or explicitly requests hash regeneration, without changing `flake.lock`; record BSL cache acceptance and license retention in packaging docs.

## 2. Database and private runtime (GP-3, GP-6)

- [x] 2.1 Add the declaration-only PostgreSQL consumer registration with non-superuser loopback authentication, PostGIS packages and administrator-owned extension setup. Verify the OCI cluster version and run migrations on a scratch database with its matching PostGIS package, without granting app superuser or upgrading unrelated cluster consumers.
- [ ] 2.2 Add the discovered `modules/apps/geopulse.nix` native runtime, dedicated user, loopback backend/frontend, private Caddy SPA/API/fixed-tile mappings and mutable paths. Land focused evaluated checks for route/listener agreement, private-by-default exposure, database relationship and absence on other hosts; validate Caddy configuration and build the host derivation without activating.
- [x] 2.3 Add service-scoped SOPS rule/template and client-secret binding contract, with operator-only RSA/encryption-key generation instructions in `docs/runbooks/geopulse.md`. Verify secret scope and credential-backed file access under the intended sandbox using non-secret fixtures. Operator creates encrypted files before host bindings force them; agents must not generate, decrypt or inspect real key material.
- [ ] 2.4 Register mutable backup capture through the existing contract and confirm the database export owns database recovery. Write upgrade/restore instructions requiring the original encryption key and a pre-Flyway export; execute a scratch export/restore test that preserves representative history and encrypted provider data without reading real production secrets.

## 3. Identity and controlled public exposure (GP-2, GP-4, GP-5)

- [x] 3.1 Add the canonical `geopulse` identity client with `/oidc/callback`, `users`-only `openid profile email`, RS256 compatibility and PKCE enforcement retained. Verify rendered provider policy and canonical discovery/callback values; document the one-time database provider entry, manual account linking and actual registration-setting precedence.
- [x] 3.2 Add the public web-policy identity with a withheld publication posture (`publish = false`; D-098 removed the GeoPulse-owned gate this was planned as). Preserve private frontend access with no public bootstrap window; test rendered configs in both gate states and public endpoint denials without source-text assertions. Write and validate the HTTPS hostname-preserving SSH-tunnel procedure for private OIDC bootstrap.
- [ ] 3.3 Complete the owner/device runbook with private first-account setup, database-owned registration closure, provider setup and source-specific Basic authentication. Document external map/geocoding/weather privacy and disabled AI/MQTT. Record the decision and placement in existing architecture docs; verify the examples match the rendered runtime and do not expose tokens in command history or logs.

## 4. Integration and operator acceptance

- [ ] 4.1 Parent runs formatting, strict OpenSpec validation, focused package/auth/config tests, three-host derivation evaluation and `just checks all` after `git add -A`. Obtain a bounded read-only review of the stable change, resolve accepted findings and retain the private gate; no public activation on merely passing lazy evaluations.
- [ ] 4.2 With operator authorization, deploy privately and prove real Kanidm login with PKCE enforced, owner recovery and closed registration; test valid/invalid/absent Basic credentials and owner-attributed location storage. Measure OCI resource use and complete scratch recovery. Only after those checks may the operator enable the public route and verify HTTPS callback, ingest and denied public surfaces. Stop on failures; bearer ingest and multi-user operation remain deferred.

## Workflow follow-up

- Archive the verified change before merge, following the owner's established sequence.
- Consider upstreaming the PKCE patch and packaging/flake only after native builds and runtime acceptance are proven.
