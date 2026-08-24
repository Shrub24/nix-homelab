# Spec: Beets Automation

## Purpose

Define transfer-safe Beets inbox/quarantine automation contracts for import, promotion, demotion, and reporting.

## Requirements

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

### Requirement: Beets failure notification uses notify CLI

The Beets automation system SHALL notify operators of runner failures via the `notify` CLI, using the `music` notification tier.

#### Scenario: Beets runner fails

- **WHEN** a `beets-*` systemd service fails
- **THEN** the `beets-notify-failure@` template unit is triggered via `OnFailure=`
- **AND** the notification script gathers the last 20 log lines from the failed service via `journalctl`
- **AND** pipes the log output to `notify music "Beets runner beets-$runner failed on $hostname"`
- **AND** if journalctl produces no output, the message body is `(no journal output)`

#### Scenario: Beets notification targets correct Telegram topic

- **WHEN** a beets runner failure notification is dispatched
- **THEN** the notification arrives in the Telegram topic mapped to the `music` tier
- **AND** the notification does NOT appear in system warning or critical topics

### Requirement: Beets notification script has no direct telegram or ntfy access

The Beets notification script SHALL NOT construct telegram URLs, read token files, or reference chat/topic IDs directly. It SHALL only call `notify` with a tier, title, and message body.

#### Scenario: Notification script is inspected

- **WHEN** an operator reads the generated `beets-notify-failure` script
- **THEN** the script contains no references to `tgram://`, `http://`, ntfy URLs, or token paths beyond the `notify` invocation
- **AND** the script's runtime dependencies are `pkgs.systemd` only (the `notify` command is available from `systemPackages`)

### Requirement: Beets notification configuration uses tier abstraction

The Beets notify configuration SHALL expose a single `tier` option that references a notification-daemon tier, replacing the previous ntfy-specific options.

#### Scenario: Operator configures beets notifications

- **WHEN** `services.beets.notify.enable = true` and `services.beets.notify.tier = "music"`
- **THEN** all beets failure notifications are routed to the `music` tier
- **AND** no ntfy URL, token, or topic options exist in the beets configuration

#### Scenario: Beets notifications disabled

- **WHEN** `services.beets.notify.enable = false`
- **THEN** no `beets-notify-failure@` systemd unit is generated
- **AND** runner failures are silent (logged only)

### Requirement: Reusable Beets framework and workflow policy MUST remain separate
The system SHALL keep reusable Beets execution scaffolding separate from music-specific workflow composition.

#### Scenario: Generic Beets mechanism is declared
- **WHEN** the Beets service layer is evaluated
- **THEN** it exposes reusable config, built-in runner kind, trigger, hook, timer, and hardening interfaces without hardcoding music ingest workflow semantics

#### Scenario: Music workflow composition is declared
- **WHEN** the music application is evaluated
- **THEN** it selects concrete Beets configs, runner instances, timers, and stage semantics through the reusable framework interface

### Requirement: Runner instances MUST be generated from built-in Beets runner kinds
The system SHALL define Beets runner instances as generated systemd service units created from built-in runner kinds, with defaulted-but-overridable args and config.

#### Scenario: Runner instance is declared
- **WHEN** a Beets runner instance is configured
- **THEN** the system generates a named systemd service unit for that runner
- **AND** the runner uses built-in behavior for its declared kind rather than an arbitrary custom command

### Requirement: Runner lifecycle extensions MUST be bounded
The system SHALL support optional pre/post command hooks and optional triggers for runner instances without turning the framework into a generic command wrapper.

#### Scenario: Timed runner with hooks is declared
- **WHEN** a Beets runner instance includes a timer trigger and pre/post commands
- **THEN** the generated unit and timer include those lifecycle extensions
- **AND** the core runner behavior still comes from the declared built-in runner kind

### Requirement: The slskd ingest trigger SHALL debounce through a settle timer
The music application SHALL trigger the ingest pipeline from slskd completions by restarting a persistent systemd timer, not by touching watched files. Each `DownloadDirectoryComplete` event SHALL re-arm the timer; the pipeline SHALL start once, after the settle window elapses with no further events.

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
