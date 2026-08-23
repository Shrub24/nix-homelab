## ADDED Requirements

### Requirement: Hosts SHALL trigger post-deploy cache pushes on system generation change
Every host that enables `services.niks3-post-deploy` SHALL push its filtered system closure to the sovereign cache whenever the system generation changes, using a trigger that fires independently of where the closure was built (local build, remote builder, or CI).

#### Scenario: System generation changes after a deploy
- **WHEN** a host activates a new system generation
- **THEN** the post-deploy push unit SHALL run after activation
- **AND** the pushed closure SHALL exclude paths signed only by the configured public cache keys

#### Scenario: Host boots with an already-pushed generation
- **WHEN** a host boots
- **THEN** the post-deploy push unit SHALL NOT start
- **AND** the activation guard SHALL skip the push because systemd is not yet running during stage-2 activation

### Requirement: Post-deploy push SHALL NOT depend on symlink path watching
The post-deploy trigger SHALL be driven from a `system.activationScripts` snippet that starts the push unit directly, because `PathChanged` on a symlink watches the resolved store directory and never fires when the symlink is re-pointed, and because a `restartTriggers` reference to `config.system.build.toplevel` is circular (the unit text would embed the toplevel path while the toplevel contains the unit text).

#### Scenario: Unit configuration is evaluated
- **WHEN** a host evaluates `systemd.services.niks3-post-deploy`
- **THEN** an activation snippet SHALL write the new toplevel path (from `$systemConfig`) to `/run/niks3-post-deploy/target`
- **AND** the snippet SHALL start the unit with `systemctl start --no-block` when systemd is running
- **AND** the unit script SHALL read the target path from `/run/niks3-post-deploy/target`, falling back to `readlink -f /run/current-system`
- **AND** no `systemd.paths` unit SHALL watch `/run/current-system`
