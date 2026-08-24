# Delta Spec: Bootstrap and Storage

## MODIFIED Requirements

### Requirement: Service-state and media mounts are separated
The storage model SHALL separate service-state and media storage at predictable, stable locations backed by stable `/dev/disk/by-id` references, where each location MAY be a dedicated filesystem mount or a directory on the root filesystem as declared per host, and a media location SHALL be present only when the host enables media workloads.

#### Scenario: Host mount contracts are validated
- **WHEN** host filesystem config is inspected
- **THEN** service-state and media locations are at distinct declared paths backed by stable `/dev/disk/by-id` references
- **AND** each location is either a dedicated mount or a root-backed directory as declared by the host
- **AND** a media location is absent on hosts that do not enable media workloads
