# Identity enrollment

## ADDED Requirements

### Requirement: ENR-1 Invitation enrollment SHALL offer two usable sign-in methods

An invited person SHALL provide username and email and choose either a user-verifying passkey without a required password, or a password plus emailed one-time codes. Every path SHALL prove ownership of the account's email before issuing a session. Password creation SHALL enforce the fleet's enrollment password-strength policy.

#### Scenario: Passkey enrollment

- **WHEN** an invited person chooses Passkey and successfully registers it
- **THEN** they SHALL verify their email before receiving a session
- **AND** they SHALL NOT be required to set a password

#### Scenario: Email-code enrollment

- **WHEN** an invited person chooses Email code and proves ownership of the supplied address
- **THEN** they SHALL set a valid password before receiving a session
- **AND** they SHALL NOT be asked to verify that unchanged address a second time in the same enrollment

#### Scenario: Invalid or absent invitation

- **WHEN** a new person starts enrollment without a valid invitation
- **THEN** enrollment SHALL NOT create an account

### Requirement: ENR-2 Login SHALL enforce the selected credential path

A passkey sign-in SHALL NOT require an additional password or OTP challenge. Password sign-in SHALL require an accepted second-step authenticator, including email OTP for users who enrolled that method. Email possession alone SHALL NOT be an ordinary login method. Existing TOTP credentials SHALL remain usable.

#### Scenario: Passkey sign-in

- **WHEN** a verified person successfully uses their user-verifying passkey
- **THEN** sign-in SHALL proceed without a password or another authenticator challenge

#### Scenario: Password and email sign-in

- **WHEN** a person supplies a correct password but has not completed the email-code challenge
- **THEN** no new login session SHALL be issued

#### Scenario: Existing TOTP account

- **WHEN** an existing password/TOTP user signs in after rollout
- **THEN** their existing credentials SHALL continue to work without forced reenrollment

### Requirement: ENR-3 Email verification SHALL represent proved address ownership

A confirmed same-user email authenticator matching the account address SHALL establish ownership without another code or device. An address without recorded verification or a matching confirmed device SHALL require a code before a session is issued. Devices for other addresses SHALL remain independent usable factors until removed by the user, but SHALL NOT verify the current address.

#### Scenario: Address changed

- **WHEN** the account email changes to an address with no matching confirmed authenticator for that user
- **THEN** its verified-email claim SHALL be false until that address is proven
- **AND** a device for another address MAY remain an authentication factor but SHALL NOT verify the current account address

#### Scenario: Persistent email authenticator remains enrolled

- **WHEN** the account email matches that user's previously confirmed email authenticator
- **THEN** ownership SHALL be recognized without sending another code, deleting the device or creating a duplicate

### Requirement: ENR-4 Incomplete enrollment SHALL be recoverable without reactivation

Signup progress SHALL NOT be encoded as administrative account disablement. An active person with a usable credential SHALL be able to sign in and complete remaining verification. An existing account with no usable credential SHALL have a mailbox-proved recovery path that establishes usable credentials without another invitation. Neither verification nor recovery SHALL enable an administratively disabled account.

#### Scenario: Abandoned before credential creation

- **WHEN** an invited person leaves after account creation but before creating any usable credential
- **THEN** mailbox-proved recovery SHALL allow them to finish establishing credentials
- **AND** knowledge of their username or address alone SHALL NOT allow completion

#### Scenario: Abandoned after passkey registration

- **WHEN** a person leaves after registering a passkey but before email verification
- **THEN** passkey sign-in SHALL lead to the remaining email challenge rather than an activation failure

#### Scenario: Recovery of an unverified reservation

- **WHEN** mailbox recovery completes for an account whose address has never been verified
- **THEN** credentials registered before ownership was established SHALL NOT give another party continued access

#### Scenario: Administrative disablement

- **WHEN** a disabled person attempts verification or recovery
- **THEN** their account SHALL remain disabled and no session SHALL be issued

### Requirement: ENR-5 Rollout SHALL preserve established identity and provide bounded repair

The change SHALL preserve existing user identifiers, application bindings and established credentials. The operator SHALL have a reviewed repair procedure for legacy accounts stranded inactive by enrollment; blanket activation SHALL NOT be part of rollout.

#### Scenario: Legacy stranded user

- **WHEN** the operator identifies an account disabled only by the previous incomplete enrollment
- **THEN** the documented repair SHALL permit verification and completion without deleting that person's established application identity
