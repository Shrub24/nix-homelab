## ADDED Requirements

### Requirement: Kanidm SHALL run a supported version line with a clean upgrade-check gate
The repo SHALL pin Kanidm to the current supported major line (`kanidm_1_11` for the server package and `kanidm_1_11` for the client/system package). The upgrade path SHALL be gated on `kanidmd domain upgrade-check` returning PASS from the running server binary before the package pin is bumped.

#### Scenario: Kanidm package is pinned to the supported line
- **WHEN** the flake evaluates `services.kanidm.package` for the identity host
- **THEN** the package resolves to `pkgs.kanidmWithSecretProvisioning_1_11` on the admin host
- **AND** `environment.systemPackages` and the host-auth default resolve to `pkgs.kanidm_1_11`

### Requirement: Kanidm offline restore verification SHALL be fail-closed with no acceptance path
The `kanidm-restore@` helper SHALL treat every nonzero offline verification result as fatal before ownership repair or service start, with no version-pinned exception predicate, no `db-scan` proof acceptance path, and no acceptance of `RefintNotUpheld` findings. Clean acceptance SHALL require exit zero, the clean-success marker, and zero error-bearing output.

#### Scenario: A nonzero offline verification result is fatal
- **WHEN** `database verify` exits nonzero during a stopped-service restore
- **THEN** the helper refuses to repair ownership or start the service
- **AND** the failure output is surfaced to the operator
- **AND** no version, finding-id, or `db-scan` proof can downgrade the failure

#### Scenario: The clean verification path is unchanged
- **WHEN** `database verify` exits zero with `Verification passed` and no error-bearing output
- **THEN** the helper proceeds to ownership repair and prints the manual-start message
