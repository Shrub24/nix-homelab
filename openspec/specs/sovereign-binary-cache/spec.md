# sovereign-binary-cache Specification

## Purpose
TBD - created by archiving change niks3-cache. Update Purpose after archive.

## Requirements

### Requirement: niks3 server SHALL run on the designated cache host
The niks3 server SHALL be deployed on `oci-melb-1` as a NixOS service with PostgreSQL backing for reference-tracking garbage collection.

#### Scenario: niks3 service is enabled
- **WHEN** `oci-melb-1` is evaluated and deployed
- **THEN** the niks3 server process is running and reachable on its configured listen address
- **AND** the service is backed by a PostgreSQL database with a dedicated niks3 user and database

#### Scenario: niks3 server restarts cleanly
- **WHEN** the niks3 service is restarted
- **THEN** it reconnects to PostgreSQL and resumes normal operation within the health-check window

### Requirement: Sovereign cache SHALL be backed by S3-compatible object storage
The niks3 server SHALL use a dedicated S3-compatible bucket (`shrublab-nix-cache` on Cloudflare R2) as its storage backend for NAR files and narinfo metadata.

#### Scenario: Push results in S3 object storage
- **WHEN** a host pushes a closure to niks3
- **THEN** the resulting NAR files and narinfo objects are stored in the configured S3 bucket
- **AND** the bucket objects are accessible for direct S3 read by configured Nix consumers

#### Scenario: S3 backend is unavailable
- **WHEN** the configured S3 backend is unreachable
- **THEN** niks3 returns appropriate errors for push requests
- **AND** the server does not crash or enter an unrecoverable state

### Requirement: Read path SHALL be native S3 without requiring an HTTP endpoint
Cache consumers SHALL read artifacts directly from the S3 bucket using standard Nix S3 substituter semantics, without routing through the niks3 server or a public HTTP cache endpoint.

#### Scenario: Nix consumer reads from sovereign cache
- **WHEN** a Nix client is configured with the S3 substituter URL and trusted public key
- **THEN** the client downloads narinfo and NAR files directly from the S3 bucket
- **AND** the niks3 server is not involved in the read data path

### Requirement: Server-side Ed25519 signing SHALL be enforced
The niks3 server SHALL hold the cache signing key and SHALL sign narinfo files on upload so that pushers do not need the signing key.

#### Scenario: Closure is pushed and verified
- **WHEN** a host pushes a closure using a valid API token
- **THEN** the niks3 server signs the resulting narinfo files with its Ed25519 signing key
- **AND** consumers that trust the corresponding public key can verify the signed narinfo

#### Scenario: Invalid signature is rejected by consumers
- **WHEN** a Nix consumer fetches a narinfo that is not signed with the trusted public key
- **THEN** the consumer rejects the artifact and does not substitute the closure

### Requirement: Reference-tracking GC SHALL manage cache retention
The niks3 server SHALL track closure references in PostgreSQL and SHALL support garbage collection with configurable retention periods and grace windows.

#### Scenario: GC removes expired unreferenced artifacts
- **WHEN** GC runs with configured retention policy
- **THEN** closures older than the retention threshold and no longer referenced are removed from S3
- **AND** closures still referenced by active deployments are preserved

#### Scenario: Grace period prevents premature GC
- **WHEN** a closure was recently pushed within the grace period
- **THEN** GC does not remove that closure even if it is unreferenced
- **AND** the grace period provides a safety window for deployments in progress

### Requirement: Push auth SHALL use host-scoped API tokens
Pushers SHALL authenticate to the niks3 server using host-scoped API tokens stored in host-specific SOPS secrets, not by sharing a single fleet-wide token.

#### Scenario: Authorized host pushes a closure
- **WHEN** a host presents a valid API token scoped to that host
- **THEN** niks3 issues pre-signed S3 upload URLs and accepts the uploaded closure

#### Scenario: Unauthorized push is rejected
- **WHEN** a client presents an invalid or missing API token
- **THEN** niks3 rejects the push request with an authentication error
- **AND** no artifacts are written to S3

### Requirement: CI SHALL NOT push to the sovereign cache
GitHub Actions workflows SHALL NOT authenticate to or push closures to the sovereign cache; push authority SHALL be reserved for hosts after successful deployment activation.

#### Scenario: CI workflow runs without cache push
- **WHEN** a GitHub Actions CI or deploy workflow executes
- **THEN** the workflow does not contain niks3 push steps or cache push credentials
- **AND** build outputs are consumed through nixbuild.net and the S3 substituter, not pushed by CI

### Requirement: Hosts SHALL trigger post-deploy cache pushes on system generation change
Every host that enables `services.niks3-post-deploy` SHALL push its filtered system closure to the sovereign cache whenever the system generation changes, using a trigger that fires independently of where the closure was built (local build, remote builder, or CI).

#### Scenario: System generation changes after a deploy
- **WHEN** a host activates a new system generation
- **THEN** the post-deploy push unit SHALL run after activation
- **AND** the pushed closure SHALL exclude paths signed only by the configured public cache keys

#### Scenario: Host boots with an already-pushed generation
- **WHEN** a host boots
- **THEN** the post-deploy push unit SHALL start after network is online
- **AND** re-running the push SHALL be a no-op against the cache (already-present paths are skipped)

### Requirement: Post-deploy push SHALL NOT depend on symlink path watching
The post-deploy trigger SHALL be driven from a `system.activationScripts` snippet that starts the push unit directly, because `PathChanged` on a symlink watches the resolved store directory and never fires when the symlink is re-pointed, and because a `restartTriggers` reference to `config.system.build.toplevel` is circular (the unit text would embed the toplevel path while the toplevel contains the unit text).

#### Scenario: Unit configuration is evaluated
- **WHEN** a host evaluates `systemd.services.niks3-post-deploy`
- **THEN** an activation snippet SHALL write the new toplevel path (from `$systemConfig`) to `/run/niks3-post-deploy/target`
- **AND** the snippet SHALL start the unit with `systemctl start --no-block` when systemd is running
- **AND** the unit script SHALL read the target path from `/run/niks3-post-deploy/target`, falling back to `readlink -f /run/current-system`
- **AND** no `systemd.paths` unit SHALL watch `/run/current-system`
