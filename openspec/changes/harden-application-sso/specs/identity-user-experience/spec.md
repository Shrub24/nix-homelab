# identity-user-experience Specification

## Purpose

Keep the fleet identity recognizable in application sign-in controls and make Authentik's desktop application list easier to scan without changing authentication identity or mobile behavior.

## ADDED Requirements

### Requirement: OIDC sign-in controls SHALL identify the provider as Shrublab

Applications that display the configured OIDC provider name SHALL present it as “Shrublab”. This display label SHALL NOT alter OIDC client IDs, provider identifiers, issuer URLs, callback URLs, subject claims, or account-linking behavior.

#### Scenario: User chooses OIDC sign-in

- **WHEN** an application renders a sign-in control from the configured OIDC provider name
- **THEN** the provider is labeled “Shrublab”
- **AND** its protocol identifiers and callback configuration remain unchanged

### Requirement: Desktop application list view SHALL align to the left

When the Authentik application dashboard is displayed in list mode at desktop widths, the list SHALL align with the left edge of the dashboard content rather than appearing as a centered column. The grid view and mobile layout SHALL remain unchanged.

#### Scenario: Desktop user selects list view

- **WHEN** the dashboard is in list mode at a desktop viewport
- **THEN** the list begins at the left edge of the available dashboard content
- **AND** its rows retain their existing layout and sizing

#### Scenario: User views the grid or a mobile dashboard

- **WHEN** the dashboard is in grid mode or rendered at a mobile viewport
- **THEN** the existing grid or mobile alignment is unchanged
