## ADDED Requirements

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
