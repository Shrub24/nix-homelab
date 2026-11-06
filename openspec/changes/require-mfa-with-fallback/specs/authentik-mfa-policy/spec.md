# Spec Delta

## Purpose

Require a second factor for every Authentik sign-in, with an email recovery route that does not depend on the device holding the passkey.

## ADDED Requirements

### Requirement: Every password sign-in SHALL require a verified second factor

MFA-1: A session created after a password SHALL require passkey, email-code or TOTP verification. A user with no enrolled method SHALL be required to enrol one before a session exists.

#### Scenario: Password user with no method enrolled

- **WHEN** a user submits a correct password and has no MFA method
- **THEN** no session is created until a method is enrolled and verified

#### Scenario: Passkey device unavailable

- **WHEN** a user with a password and an authenticator code lacks their passkey device
- **THEN** they can choose the authenticator code on the MFA screen and sign in

### Requirement: Passkey sign-in SHALL remain one step

MFA-2: Signing in with a user-verified passkey from the username field SHALL skip the password and MFA stages.

#### Scenario: Passkey autofill

- **WHEN** a user selects a registered passkey from the username field
- **THEN** they are signed in without a password or further factor

### Requirement: A lost device SHALL be recoverable by email in one flow

MFA-3: The email recovery flow SHALL be reachable without a credential and SHALL, in one flow, prove the current mailbox, establish a usable email authenticator and set a strength-checked password before creating a session. It SHALL NOT force TOTP enrollment or reactivate a disabled account.

#### Scenario: Passkey device lost

- **WHEN** a user without their passkey device requests recovery and follows the emailed link
- **THEN** mailbox proof establishes an email authenticator and they set a strong password
- **AND** the session is created only after completion
- **AND** subsequent password/email-code sign-in works

### Requirement: Enrollment SHALL require a method

MFA-4: Invitation enrollment SHALL NOT complete until the new user has enrolled a passkey, email authenticator or TOTP and proven the account address. A password SHALL be required only without a confirmed passkey.

#### Scenario: Optional passkey previously skipped

- **WHEN** a new user completes the details step without enrolling a method
- **THEN** the flow continues to required setup rather than creating a session

### Requirement: Recovery SHALL NOT leave an account without a method

MFA-5: A recovery session SHALL NOT be created until at least one MFA method is enrolled.

#### Scenario: Recovery with no method enrolled

- **WHEN** a user with no enrolled method completes the password step of recovery
- **THEN** mailbox proof has established an email authenticator before the session exists
- **AND** pre-verification credentials on a never-verified reservation cannot authenticate after recovery

### Requirement: The panel SHALL NOT change size between screens

MFA-6: On desktop the login pane SHALL keep one size and logo position across login, MFA, setup, recovery and enrollment screens.

#### Scenario: Moving to the MFA screen

- **WHEN** the flow moves from the password to the MFA screen
- **THEN** the pane size and logo position are unchanged
