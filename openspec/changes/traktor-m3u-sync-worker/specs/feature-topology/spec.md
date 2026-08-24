## ADDED Requirements

### Requirement: Upstream-packaged music workers MAY be composed as optional leaf features
The system SHALL allow upstream-packaged music workers to be composed through the music application layer when the repository only needs to provide fleet-specific paths, enablement, and operational policy.

#### Scenario: Music app composes an upstream Traktor worker
- **WHEN** the music application enables the Traktor playlist sync worker
- **THEN** the worker SHALL remain an optional leaf feature
- **AND** the application layer SHALL own shared path defaults and enablement
- **AND** host files SHALL NOT duplicate upstream package or service internals
