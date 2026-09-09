# Delta Spec: Secrets Management

## ADDED Requirements

### Requirement: Tailscale auth-key registration SHALL be module-owned with unchanged readership
The Tailscale module SHALL own registration of the conventional host-scoped Tailscale auth-key secret — sourced from the host system secret scope under key `tailscale/auth_key` and rendered to `/run/secrets/tailscale.auth_key` — and host assemblies SHALL NOT repeat that `sops.secrets` registration. Recipient policy in `.sops.yaml` SHALL remain unchanged and independent of module ownership.

#### Scenario: Host enables Tailscale
- **WHEN** a host enables the Tailscale aspect
- **THEN** the module registers the Tailscale auth-key secret through its own contract using the conventional host-scoped secret path
- **AND** the host assembly contains no duplicated `sops.secrets` entry for the Tailscale auth key

#### Scenario: Recipient policy and ciphertext are unchanged
- **WHEN** the change is implemented and evaluated
- **THEN** the `.sops.yaml` host system scope reader sets are unchanged
- **AND** no existing encrypted secret file is edited or re-encrypted as part of the change
