## ADDED Requirements

### Requirement: Private Niks3 writes SHALL use an internal transport contract

Hosts publishing closures SHALL resolve the Niks3 private write endpoint from the canonical `niks3Write` internal contract. The contract SHALL remain distinct from the cache read/substituter identity.

#### Scenario: Remote host publishes a closure

- **WHEN** a non-cache host invokes the Niks3 upload client
- **THEN** its server URL uses the provider hostname and port resolved from the internal write contract
- **AND** it does not embed the current cache host name

#### Scenario: Cache host publishes locally

- **WHEN** the Niks3 provider host publishes its own closure
- **THEN** it may use a provider-local loopback endpoint as an explicit transport optimization
- **AND** remote publishers continue to use the resolved private contract

#### Scenario: Consumer reads from the cache

- **WHEN** a Nix consumer substitutes a closure
- **THEN** it continues to use the canonical read/substituter policy
- **AND** it does not route reads through the private write contract
