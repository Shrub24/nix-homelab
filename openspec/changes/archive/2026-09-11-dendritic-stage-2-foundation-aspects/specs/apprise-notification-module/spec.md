# Delta Spec: Apprise Notification Module

## ADDED Requirements

### Requirement: Notification aspect SHALL guarantee daemon composition for fleet consumers
The notification foundation aspect SHALL own daemon availability by composing the notification-daemon module, so fleet consumers such as backup monitoring can rely on the daemon wherever the aspect is enabled without each host or consumer importing the module leaf separately.

#### Scenario: Backup monitoring relies on the notification aspect
- **WHEN** a host enables the notification foundation aspect and runs backup monitoring
- **THEN** the notification-daemon module is composed and available to the monitor
- **AND** the monitor does not need its own notification-daemon module import

#### Scenario: Host configuration remains host-specific
- **WHEN** a host enables the notification aspect
- **THEN** the host still provides only host-specific inputs through the module's established secret contract
- **AND** the aspect guarantees the daemon, CLI, and monitor composition