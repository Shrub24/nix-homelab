# Spec: Navidrome Scan Trigger

## Purpose

Provide a local Navidrome scan unit and trigger it after successful Beets inbox processing.

## Requirements

### Requirement: Navidrome scan unit is available for local automation
The system SHALL provide a local systemd oneshot unit that runs Navidrome's supported CLI scan command using the configured Navidrome package and runtime folders.

#### Scenario: Scan unit is rendered
- **WHEN** Navidrome is enabled
- **THEN** a `navidrome-scan.service` oneshot unit is available
- **AND** the unit uses the configured `services.navidrome.package`
- **AND** the scan command includes the configured Navidrome data folder and music folder

#### Scenario: Scan unit runs with Navidrome access
- **WHEN** `navidrome-scan.service` starts
- **THEN** it runs as the Navidrome service user and group
- **AND** it has the same media access groups needed to read managed music paths
- **AND** it declares mount prerequisites for the data and music paths

### Requirement: Beets inbox success triggers Navidrome scan
The system SHALL trigger the local Navidrome scan unit after the Beets inbox service completes successfully.

#### Scenario: Beets inbox succeeds
- **WHEN** `beets-inbox.service` completes successfully
- **THEN** systemd starts `navidrome-scan.service`

#### Scenario: Beets inbox fails
- **WHEN** `beets-inbox.service` fails
- **THEN** systemd SHALL NOT start `navidrome-scan.service` through the success chain
