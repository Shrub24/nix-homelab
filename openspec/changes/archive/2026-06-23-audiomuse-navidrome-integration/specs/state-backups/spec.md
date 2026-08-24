# Delta Spec: State Backups

## ADDED Requirements

### Requirement: AudioMuse backups SHALL prioritize durable database state
AudioMuseAI backup coverage SHALL distinguish durable PostgreSQL state from non-canonical Redis queue/cache and temp working data.

#### Scenario: AudioMuse backup policy is reviewed
- **WHEN** AudioMuseAI participates in host state backup coverage
- **THEN** PostgreSQL-backed AudioMuse state SHALL be included as the primary durable recovery target, noting that this is the **existing shared Postgres instance** (`services.postgres-shared`), not a dedicated AudioMuse-local Postgres volume
- **AND** Redis and temp audio working paths SHALL NOT be treated as canonical backup state unless implementation validation proves they are required for recovery
- **AND** media library payloads under `/srv/media` SHALL remain governed by host media backup policy rather than AudioMuse service policy
