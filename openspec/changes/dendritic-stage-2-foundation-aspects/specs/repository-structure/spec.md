# Delta Spec: Repository Structure

## ADDED Requirements

### Requirement: Converted compatibility roots SHALL leave the temporary import-tree exclusion boundary
Once every file under `modules/core/` and `modules/profiles/` has become a Dendritic aspect contributor or has been relocated or deleted, those directories SHALL be removed from the single temporary import-tree exclusion boundary; the boundary SHALL continue to enumerate only directories that still contain non-contributing leaves, and no second permanent module discovery root SHALL be introduced.

#### Scenario: Core and profiles complete conversion
- **WHEN** all leaves under `modules/core/` and `modules/profiles/` contribute through the aspect registry or are removed
- **THEN** the temporary import-tree exclusion boundary no longer lists `core` or `profiles`
- **AND** any remaining exclusions stay enumerable and removable within the same single explicit boundary

#### Scenario: Legacy bundles are decomposed rather than preserved as wrappers
- **WHEN** a legacy profile bundle (`base-server`, `fleet-standard`, or `networking`) or a legacy core wrapper no longer has a unique contribution
- **THEN** it is decomposed into aspect contributors or relocated/deleted rather than preserved as a permanent compatibility aspect
- **AND** the host assemblies no longer reference the removed wrapper
