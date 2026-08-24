## MODIFIED Requirements

### Requirement: Media services remain mount-aware and permission-reconciling
Media services SHALL declare mount prerequisites and SHALL reconcile permissions after promotion/sync operations where required. Permission reconciliation SHALL run as root via a standalone service, decoupled from the beets runner framework.

#### Scenario: Service units enforce mount and permission integrity
- **WHEN** media service units are evaluated
- **THEN** required mounts are declared and permission reconciliation hooks remain part of operational flow

#### Scenario: Permission reconciliation runs as root
- **WHEN** permission reconciliation is triggered (manually or via `OnSuccess=` from a media service)
- **THEN** the `media-permission-reconcile.service` runs as root
- **AND** it applies `chgrp music-ingest`, `chmod 2775/0664`, and `setfacl` rules to library, quarantine, untagged, and approved directories
- **AND** the service is not coupled to the beets runner framework

#### Scenario: Beets services trigger permission reconciliation and Navidrome scan via OnSuccess
- **WHEN** any beets runner service completes successfully
- **THEN** `media-permission-reconcile.service` and `navidrome-scan.service` are triggered via `OnSuccess=` chaining
- **AND** the `onSuccessUnits` list is a module-level option set by the application composition layer, not hardcoded in the beets framework
- **AND** no `ExecStartPost` with privilege escalation is used
