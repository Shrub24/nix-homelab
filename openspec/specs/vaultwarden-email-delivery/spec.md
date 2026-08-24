# Spec: Vaultwarden Email Delivery

## Purpose

Define the delivery and DNS contract for Vaultwarden email on `la-admin-1` using a provider-verified sending domain.

## Requirements
### Requirement: Vaultwarden SMTP delivery SHALL support a dedicated provider-verified sending domain
Vaultwarden delivery for `la-admin-1` SHALL support SMTP configuration that sends mail from a dedicated provider-verified sending domain rather than relying on ad hoc personal-mail settings.

#### Scenario: Vaultwarden SMTP runtime is rendered
- **WHEN** `services.admin.vaultwarden` is enabled for `la-admin-1`
- **THEN** SMTP host, port, sender identity, and authentication inputs are declared for provider-backed delivery
- **AND** the configured sender address is scoped to the dedicated sending domain used for provider verification

### Requirement: Sending-domain DNS inputs SHALL be declarative and provider-oriented
The Cloudflare OpenTofu layer SHALL support declarative SPF, MX, DKIM, and optional DMARC records for the sending domain, with tfvars able to carry provider-specific names and values directly where those values can vary by provider or region.

#### Scenario: Operator copies values from provider dashboard
- **WHEN** Resend or another mail provider presents exact DNS verification strings
- **THEN** the OpenTofu variable surface accepts those provider-oriented values without requiring hidden transformations for variable parts

### Requirement: Public sending-domain verification data SHALL remain non-secret
DKIM, SPF, MX, and DMARC record content used for public DNS verification SHALL be stored in non-secret configuration, while SMTP/API credentials remain secret-scoped.

#### Scenario: DNS verification material is reviewed
- **WHEN** the sending-domain configuration is inspected
- **THEN** public DNS record values are present in ordinary OpenTofu config
- **AND** authentication secrets are stored only in encrypted secret inputs or host-scoped secret templates
