## ADDED Requirements

### Requirement: Operations SHALL document manual Traktor playlist sync validation
Operations documentation SHALL describe how to run the Traktor playlist export/import jobs manually, validate generated playlists, run the repository validation workflow, and avoid unsafe automatic import loops during the first iteration.

#### Scenario: Operator validates export before import
- **WHEN** the operator deploys Traktor playlist sync for the first time
- **THEN** the workflow SHALL direct the operator to run export manually first
- **AND** inspect generated M3U paths before attempting import
- **AND** confirm the collection file path and Traktor-to-host path mapping are correct
- **AND** run `just check` before deploy, with `openspec validate` as the supplementary artifact validation

#### Scenario: Operator tests import with a curated directory
- **WHEN** the operator tests M3U import back into Traktor collection state
- **THEN** the workflow SHALL use the configured import directory rather than the export output directory
- **AND** the operator SHALL verify upstream collection backups exist before accepting the import result
