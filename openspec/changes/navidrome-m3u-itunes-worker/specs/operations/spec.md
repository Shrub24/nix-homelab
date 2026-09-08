## ADDED Requirements

### Requirement: Navidrome playlist sync SHALL be reproducible
Operators SHALL run `playlist-sync` on `home-forge` to fetch `/music`-rooted M3Us into the import dir and start the import job, then validate the chained engine export in Engine DJ before relying on it.

#### Scenario: Operator performs a playlist sync
- **WHEN** the operator runs `playlist-sync` on `home-forge`
- **THEN** the import job starts and the engine export chains via `onSuccess`
- **AND** the operator inspects either job's failure before validating in Engine DJ

#### Scenario: Sync is rolled back
- **WHEN** a synced playlist fails Engine DJ validation
- **THEN** the operator removes or replaces only the worker SQLite state and reverts the affected Engine database entries
- **AND** no Navidrome playlist or media file is modified by the worker
