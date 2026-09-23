# opentofu-state-recovery Specification

## Purpose
Define how the Cloudflare OpenTofu state is recovered deterministically: imports limited to resources the stack declares, and a post-recovery plan comparison that separates real drift from provider noise.
## Requirements
### Requirement: OpenTofu Cloudflare state recovery SHALL be runbook-driven and deterministic
The Cloudflare OpenTofu stack SHALL provide a documented, deterministic recovery workflow that maps declared resource addresses to live Cloudflare IDs and restores state ownership without ad-hoc address conventions.

#### Scenario: Declared-resource recovery is executed
- **WHEN** operator runs recovery for stale/desynced state
- **THEN** imports target only resources declared in `opentofu/cloudflare/main.tf`
- **AND** post-recovery `tofu plan` is used to identify remaining semantic drift versus noise

### Requirement: Recovery workflow SHALL distinguish noise from semantic drift
The recovery contract SHALL identify provider normalization-only diffs separately from real resource-policy intent changes.

#### Scenario: Access application diffs are reviewed after import
- **WHEN** plan includes Access app changes
- **THEN** null/false normalization-only fields are treated as noise candidates
- **AND** idp/policy remaps or route membership changes are treated as semantic drift requiring explicit operator decision

