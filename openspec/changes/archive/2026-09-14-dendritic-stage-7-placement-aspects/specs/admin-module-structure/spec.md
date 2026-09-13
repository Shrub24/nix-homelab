## MODIFIED Requirements

### Requirement: Admin modules SHALL follow layered ownership boundaries
Admin configuration SHALL keep policy data under `policy/`, policy transformation logic under `lib/`, and service-owned behavior in concern-owned private implementations. Deployment composition SHALL be published by the discovered `identity-provider`, `cockpit`, and `admin-hub` contributors rather than retained under a permanent `modules/applications/admin/` evaluator-class root. Host-local assembly SHALL retain only explicit variants and machine-specific exceptions under `modules/hosts/<host>/`.

#### Scenario: Admin module tree is reviewed
- **WHEN** operators inspect admin-related repository paths
- **THEN** Kanidm server/provisioning composition is owned by the `identity-provider` concern
- **AND** independently placed Cockpit composition is owned by the `cockpit` concern
- **AND** the coupled Termix, Vaultwarden, Homepage, Gatus, Beszel hub, Webhook, and current Quantum policy are owned by the `admin-hub` concern
- **AND** private service implementations are located beside those concern owners or remain temporarily under the service migration root
- **AND** host-local admin overlays contain only genuine host variants and do not directly import implementations
- **AND** policy data and transforms are not embedded in service or host files
- **AND** no `modules/applications/admin/` compatibility wrapper remains
