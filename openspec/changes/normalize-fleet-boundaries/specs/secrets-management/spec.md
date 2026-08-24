# Delta Spec: Secrets Management

## ADDED Requirements

### Requirement: Conventional host service secrets SHALL resolve through module-owned defaults
Secret registration for conventional host-scoped service inputs (for example `tailscale_auth_key`, Cockpit service-user password hashes, Beszel agent tokens, and niks3 API tokens under `secrets/hosts/<host>/system.yaml`) SHALL be owned by the consuming service or application module as typed defaults keyed off the host's conventional system secret path, so host assemblies do not repeat raw `sops.secrets` definitions.

#### Scenario: Host enables a service that reads its host system secret scope
- **WHEN** a host enables a service whose secrets conventionally live in that host's system scope
- **THEN** the module registers the secret through its own contract surface using the conventional path
- **AND** the host file does not define the corresponding `sops.secrets` entry

#### Scenario: Host binds an explicit secret source override
- **WHEN** a host overrides the conventional secret source for an enabled feature
- **THEN** the override flows through the module's explicit contract input
- **AND** evaluation/assertion checks still verify the referenced secret file exists and has not drifted

### Requirement: Secret-scope test expectations SHALL remain explicit while sharing mechanical topology data
The secret-scope regression check SHALL keep per-scope expected reader sets explicit so accidental recipient widening still fails, while allowing the fixture to share only mechanical host identity data (host name to age-recipient mapping) with topology sources.

#### Scenario: A host recipient is accidentally added to an unrelated scope
- **WHEN** `.sops.yaml` adds a host recipient to a scope outside its expected reader set
- **THEN** the check fails and names the unexpected reader
- **AND** fixture de-duplication does not mask the failure

#### Scenario: Host identity data is shared mechanically
- **WHEN** the scope fixture and physical topology metadata share the host-name to recipient mapping
- **THEN** only the mechanical mapping is derived from a shared source
- **AND** each scope's expected reader set remains explicitly declared in the fixture
