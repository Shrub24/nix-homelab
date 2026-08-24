# Delta Spec: Repository Structure

## MODIFIED Requirements

### Requirement: Host and module boundaries are explicit
Repository structure SHALL separate host composition from reusable module domains and SHALL preserve explicit layering between policy data (`policy/`), policy transformation helpers (`lib/`), service-owned modules (`modules/services/`), feature-domain service subtrees such as `modules/services/music/`, application composition (`modules/applications/`), host assembly (`hosts/`), and topology-aligned secret scopes (`secrets/`).

#### Scenario: Operator navigates repository
- **WHEN** codebase layout is reviewed
- **THEN** host identity, application composition, leaf service implementation, and secret scopes are clearly separated by directory and ownership boundaries
- **AND** admin/media/service implementation and host-local assembly are not collapsed into one file or one monolithic secret bucket
- **AND** music-owned service implementation files are discoverable under a coherent music service subtree

### Requirement: Documentation authority is centralized
Architecture/decision/process documents SHALL remain centralized and referenced by entrypoint docs to avoid drift, including when module and host layout changes are introduced.

#### Scenario: Structure or workflow changes are introduced
- **WHEN** significant layout/workflow updates are made
- **THEN** authoritative docs are updated in the same change window
- **AND** module path examples are updated when music services are regrouped under `modules/services/music/`
