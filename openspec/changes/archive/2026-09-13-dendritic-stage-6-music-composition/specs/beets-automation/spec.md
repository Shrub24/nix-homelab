## MODIFIED Requirements

### Requirement: Beets processing is transfer-safe
The Beets runner SHALL use transfer-safety controls (including temporary-file lockout and settle timing) before processing files. The Beets inbox service SHALL trigger downstream post-success automation through systemd only after the inbox service completes successfully. The ffmpeg-preprocess and path ingest units SHALL be owned by the music implementation leaf, while their observable trigger behavior remains unchanged.

#### Scenario: Inbox processing is triggered
- **WHEN** Beets runner starts against a target path
- **THEN** transfer-safety checks run before import and move operations

#### Scenario: Inbox trigger sources are event-driven
- **WHEN** slskd completes a download directory
- **THEN** the slskd `DownloadDirectoryComplete` event restarts `slskd-settle.timer`, which starts `ffmpeg-preprocess.service` after the settle window elapses
- **AND** `ffmpeg-preprocess.service` chains to `beets-inbox.service` via `OnSuccess`
- **WHEN** Syncthing or manual drops land in the dropbox directory
- **THEN** a `PathModified` path unit starts `ffmpeg-preprocess.service` directly
- **AND** path units declare their trigger target in `[Path]` via `pathConfig.Unit`, never as an unknown `[Unit]`-section key

#### Scenario: Successful inbox service triggers downstream automation
- **WHEN** `beets-inbox.service` completes successfully
- **THEN** systemd starts its configured post-success unit dependencies

#### Scenario: Failed inbox service does not trigger downstream automation
- **WHEN** `beets-inbox.service` fails
- **THEN** systemd SHALL NOT start its post-success unit dependencies

### Requirement: Reusable Beets framework and workflow policy MUST remain separate
The system SHALL keep reusable Beets execution scaffolding separate from music-specific workflow composition. The reusable framework leaf SHALL own Beets secret registration, rendered config-template assembly, the operator CLI binaries generated from built-in runner kinds, and concrete runner runtime/hardening, while the music workflow composition SHALL retain selection of configs, runner instances, and the `OnSuccess` chain intent.

#### Scenario: Generic Beets mechanism is declared
- **WHEN** the Beets service layer is evaluated
- **THEN** it exposes reusable config, built-in runner kind, trigger, hook, timer, and hardening interfaces without hardcoding music ingest workflow semantics

#### Scenario: Music workflow composition is declared
- **WHEN** the music application is evaluated
- **THEN** it selects concrete Beets configs, runner instances, timers, and stage semantics through the reusable framework interface

#### Scenario: Beets implementation ownership is leaf-owned
- **WHEN** the reusable Beets leaf registers secrets, assembles rendered config templates, generates operator CLI binaries, or applies runner runtime/hardening
- **THEN** that implementation ownership lives in the leaf rather than the music workflow composition
- **AND** existing secret names, template paths, operator binary names, runner unit behavior, and `OnSuccess` chaining remain unchanged

### Requirement: The slskd ingest trigger SHALL debounce through a settle timer
The music application SHALL trigger the ingest pipeline from slskd completions by restarting a persistent systemd timer, not by touching watched files. Each `DownloadDirectoryComplete` event SHALL re-arm the timer; the pipeline SHALL start once, after the settle window elapses with no further events. The settle timer and its polkit rule SHALL be owned by the music implementation leaf, while their observable timing and authorization behavior remain unchanged.

#### Scenario: Download directory completes
- **WHEN** slskd fires `DownloadDirectoryComplete`
- **THEN** the integration hook runs `systemctl try-restart slskd-settle.timer`
- **AND** the hook performs no filesystem writes outside its own namespace

#### Scenario: Concurrent completions coalesce
- **WHEN** multiple completion events fire within the settle window
- **THEN** each event re-arms the timer
- **AND** exactly one pipeline run occurs after the last event

#### Scenario: Boot catch-up replaces the retry timer
- **WHEN** a host boots with unprocessed media in the inbox
- **THEN** the persistent settle timer starts `ffmpeg-preprocess.service`
- **AND** no per-boot retry timer exists for beets import runners

#### Scenario: Unprivileged hook may restart only the settle timer
- **WHEN** the `slskd` user attempts to manage any systemd unit other than `slskd-settle.timer`
- **THEN** polkit denies the action
- **AND** restarting `slskd-settle.timer` is allowed without interactive authentication
