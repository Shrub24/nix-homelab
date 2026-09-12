## MODIFIED Requirements

### Requirement: Stage instantiation MUST be application-owned
The system SHALL keep concrete Beets stage instantiation under the music application layer rather than embedding it as fixed behavior in the generic Beets service framework.

#### Scenario: Stage runners are declared
- **WHEN** the music application composes Beets workflow stages
- **THEN** it declares which runner instances exist, which configs they use, and which timers or manual invocation paths apply
- **AND** Beets config assets are owned under `modules/services/music/beets/files/`
