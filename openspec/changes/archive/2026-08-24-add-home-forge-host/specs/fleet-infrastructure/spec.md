# Delta Spec: Fleet Infrastructure

## MODIFIED Requirements

### Requirement: Storage model separates service state and media
The system SHALL maintain predictable persistent storage locations for service state and media using stable `/dev/disk/by-id` device references, where each location MAY be backed by either a dedicated filesystem mount or a directory on the root filesystem as declared per host, and a media location SHALL be declared only when the host enables media workloads.

#### Scenario: Storage contracts are rendered
- **WHEN** host storage modules are evaluated
- **THEN** service-state and media locations are declared at predictable stable paths with stable `/dev/disk/by-id` device references
- **AND** each location is either a dedicated filesystem mount or a directory on the root filesystem as declared by the host
- **AND** a media location is present only on hosts that enable media workloads
