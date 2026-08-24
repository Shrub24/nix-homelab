## MODIFIED Requirements

### Requirement: Processing outcome is deterministic
Beets automation SHALL produce deterministic outcomes for promoted, non-promoted, and crash-interrupted files according to configured rules. On runner crash (non-zero exit), demotion SHALL NOT execute, leaving unseen files in the import target for automatic retry or manual recovery.

#### Scenario: Mixed importability files are processed
- **WHEN** import succeeds for some files and not others
- **THEN** successful files are promoted and unresolved files follow demotion rules
- **AND** duplicate candidates in automated stages follow configured non-interactive policy

#### Scenario: Interactive quarantine import succeeds
- **WHEN** an operator accepts one or more files during `beets-interactive`
- **THEN** accepted files are promoted into the explicit Navidrome library path
- **AND** leftover unresolved media remains under the quarantine retry boundary
- **AND** permission reconciliation and Navidrome scan automation run after successful completion

#### Scenario: Interactive quarantine item is skipped
- **WHEN** an operator skips or leaves an item unresolved during `beets-interactive`
- **THEN** the item remains retryable in quarantine
- **AND** the system SHALL NOT create a confusing imported-as-is entry that hides the file from normal library discovery

#### Scenario: Runner crashes mid-import
- **WHEN** the beets import process exits non-zero (crash) before completing all files
- **THEN** demotion SHALL NOT execute
- **AND** unseen files SHALL remain in the import target path
- **AND** the runner SHALL exit with the non-zero code to trigger systemd failure hooks

### Requirement: Beets processing is transfer-safe
The Beets runner SHALL use transfer-safety controls (including temporary-file lockout and settle timing) before processing files. The Beets inbox service SHALL trigger downstream post-success automation through systemd only after the inbox service completes successfully.

#### Scenario: Inbox processing is triggered
- **WHEN** Beets runner starts against a target path
- **THEN** transfer-safety checks run before import and move operations

#### Scenario: Inbox trigger sources are event-driven
- **WHEN** slskd completes a download directory
- **THEN** the slskd `DownloadDirectoryComplete` event fires a debounced hook that touches a trigger file
- **AND** a systemd path unit watches the trigger file and starts `ffmpeg-preprocess.service`
- **AND** `ffmpeg-preprocess.service` chains to `beets-inbox.service` via `OnSuccess`
- **WHEN** Syncthing or manual drops land in the dropbox directory
- **THEN** a `PathModified` path unit starts `ffmpeg-preprocess.service` directly

#### Scenario: Successful inbox service triggers downstream automation
- **WHEN** `beets-inbox.service` completes successfully
- **THEN** systemd starts its configured post-success unit dependencies

#### Scenario: Failed inbox service does not trigger downstream automation
- **WHEN** `beets-inbox.service` fails
- **THEN** systemd SHALL NOT start its post-success unit dependencies

### Requirement: Runtime and state paths are explicit
Beets SHALL use explicit module-injected media/data paths for runtime state, logs, rendered config template access, and import destination paths.

#### Scenario: Service units are rendered
- **WHEN** Beets units and runner environment are generated
- **THEN** path usage derives from declared options instead of hardcoded filesystem literals
- **AND** hardened service units include required access paths to rendered config templates

#### Scenario: Beets configs are rendered
- **WHEN** standard and quarantine Beets configs are rendered
- **THEN** their library database path and media destination path are explicit
- **AND** the media destination path points at the managed Navidrome library

#### Scenario: Conversion is handled before import
- **WHEN** files arrive in the staging directory
- **THEN** ffmpeg-preprocess converts lossless formats to AIFF before beets import
- **AND** the beets convert plugin SHALL NOT be enabled to avoid temp file name leakage into the path template

### Requirement: Automation remains operationally controllable
Beets execution SHALL support operator-controlled manual rescue processing after SoulSync cutover, and beets-inbox SHALL NOT remain the default primary automated ingest/promotion backend.

#### Scenario: Operator executes manual rescue run
- **WHEN** beets runner is invoked manually against an approved rescue boundary
- **THEN** processing occurs within declared boundary checks and logs are emitted to state paths
- **AND** this execution is fallback-oriented rather than the canonical default ingest path

#### Scenario: Operator inspects interactive logs
- **WHEN** an operator runs `beets-interactive` through the CLI wrapper
- **THEN** output is persisted in `/srv/data/beets/logs/`
- **AND** useful output is available in journald under a predictable `beets-interactive` transient unit name


