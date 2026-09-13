## ADDED Requirements

### Requirement: Cross-host PostgreSQL consumers SHALL use the internal service contract

Consumers running on another host SHALL resolve the shared PostgreSQL private hostname and port from the canonical PostgreSQL internal contract rather than embedding the current provider machine name.

#### Scenario: AudioMuse connects to shared PostgreSQL

- **WHEN** AudioMuse evaluates on home-forge while PostgreSQL is provided by OCI
- **THEN** its PostgreSQL host and port resolve from the internal service contract
- **AND** the AudioMuse host configuration does not contain the literal provider host name

#### Scenario: PostgreSQL placement changes

- **WHEN** the PostgreSQL contract provider changes to another capable canonical host
- **THEN** cross-host consumers resolve the new endpoint without editing their feature configuration
- **AND** validation requires the new provider to select the PostgreSQL aspect
