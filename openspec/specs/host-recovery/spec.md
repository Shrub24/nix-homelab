# host-recovery Specification

## Purpose
TBD - created by archiving change add-host-recovery-baseline. Update Purpose after archive.

## Requirements

### Requirement: Remote hosts SHALL provide a declared recovery baseline
Remote hosts that opt into the recovery baseline SHALL provide a declared break-glass path that includes a host-scoped console rescue operator path and a routine reboot exercise.

#### Scenario: Recovery baseline is enabled for a host
- **WHEN** a host enables the recovery capability
- **THEN** the host configuration declares a separate console rescue operator path and a recurring reboot exercise as part of the host baseline

### Requirement: Console rescue access SHALL be independent from normal host login flow
Console rescue access SHALL use dedicated host-scoped password material and SHALL remain separate from the normal SSH and identity-backed login path.

#### Scenario: Console rescue configuration is reviewed
- **WHEN** the host recovery baseline is inspected
- **THEN** console rescue access uses explicit dedicated host-scoped password material
- **AND** the normal host login flow does not depend on that rescue access path

### Requirement: Rescue operator access SHALL remain explicit and host-scoped
The recovery baseline SHALL support a host-scoped rescue operator identity that is console-only, password-authenticated, explicitly declared, and reserved for break-glass administration.

#### Scenario: Rescue operator identity is rendered
- **WHEN** a host enables rescue operator access
- **THEN** the rescue identity is declared explicitly for that host
- **AND** access is available at the provider or serial console without enabling routine SSH login for that account

### Requirement: Recovery readiness SHALL be exercised routinely
Hosts that enable the recovery baseline SHALL exercise restart recovery on a declared recurring schedule so recovery drift is detected before an emergency.

#### Scenario: Recovery exercise schedule is reviewed
- **WHEN** host timers and recovery policy are inspected
- **THEN** a declared recurring reboot exercise exists for the host
- **AND** the cadence is explicit rather than implicit in unrelated update behavior

### Requirement: LA authority SHALL require verified independent recovery paths
Before LA becomes the public edge and identity authority, it SHALL have a provider-console recovery procedure, a console-only SOPS-backed `rescue` account, and verified declarative operator SSH access independent of password authentication.

#### Scenario: First LA boot recovery verification
- **WHEN** the first fleet generation has booted on LA
- **THEN** the operator verifies key-based `dev` SSH and provider-console `rescue` login
- **AND** password SSH is not required for either recovery path

### Requirement: Operator and recovery shells SHALL remain distinct on the first boot
The fleet SHALL provision `dev` as the managed interactive operator account and make its Zsh startup file available during the first configured boot. The shared `root` recovery-login account SHALL use a minimal interactive Bash shell and SHALL NOT inherit the operator Zsh prompt, plugin, or alias configuration. The console-only `rescue` account SHALL remain an explicit minimal Bash recovery path.

#### Scenario: First operator login after a boot activation
- **WHEN** the first fleet generation has booted and the operator logs in as `dev`
- **THEN** the managed Zsh startup file already exists
- **AND** Zsh does not invoke its new-user installer
- **AND** `root` and `rescue` retain interactive Bash shells
