## ADDED Requirements

### Requirement: Open WebUI Computer connections SHALL remain user-owned and opt-in
The system SHALL not host a shared Open WebUI Computer instance. A user MAY expose a selected workspace from their own `cptr` installation as an OpenAI-compatible gateway reachable over Tailscale.

#### Scenario: A user opts in a personal workspace
- **WHEN** a user creates a Computer gateway key for a selected personal workspace
- **THEN** the workspace remains on the user's own machine
- **AND** the hosted Open WebUI instance can reach its gateway only over the declared private network path

### Requirement: Curated Computer connections SHALL have explicit model access
The baseline onboarding flow SHALL require an operator to register a user-provided Computer gateway connection and SHALL restrict its resulting `cptr/<workspace>` model to the intended Open WebUI user or group.

#### Scenario: A curated connection is registered
- **WHEN** an operator adds a user's Computer gateway to Open WebUI
- **THEN** the connection uses the user-provided endpoint and gateway credential
- **AND** model access control prevents unrelated users from selecting that workspace model

### Requirement: Computer connection limits SHALL be documented
The system SHALL document that Computer gateway execution has the authority of the user-owned machine, that hosted Open WebUI identity is not forwarded as Computer identity, and that experimental Direct Connections are not the fleet baseline.

#### Scenario: A user considers self-service connection
- **WHEN** a user evaluates browser-direct Computer connectivity
- **THEN** documentation identifies it as experimental and requires browser-to-device CORS and Tailscale reachability
- **AND** it does not replace curated onboarding without a separate security decision
