## MODIFIED Requirements

### Requirement: Vaultwarden SMTP delivery SHALL support a dedicated provider-verified sending domain
Vaultwarden delivery for `la-admin-1` SHALL support SMTP configuration that sends mail from a dedicated provider-verified sending domain rather than relying on ad hoc personal-mail settings.

#### Scenario: Vaultwarden SMTP runtime is rendered
- **WHEN** `services.admin.vaultwarden` is enabled for `la-admin-1`
- **THEN** SMTP host, port, sender identity, and authentication inputs are declared for provider-backed delivery
- **AND** the configured sender address is scoped to the dedicated sending domain used for provider verification
