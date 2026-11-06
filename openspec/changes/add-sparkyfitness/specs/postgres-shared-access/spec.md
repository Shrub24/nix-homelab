## ADDED Requirements

### Requirement: PG-1 — A consumer database SHALL support additional restricted login roles

The shared PostgreSQL consumer contract SHALL provision additional password logins and permitted connection sources for one consumer database while retaining its single owner. Additional logins SHALL NOT acquire ownership, owner-role membership, superuser or cluster-wide role-creation privileges through registration.

#### Scenario: Owner and application login are provisioned

- **WHEN** a consumer declares a migration owner and an additional application login
- **THEN** both roles can authenticate to the consumer's database from its permitted connection sources
- **AND** the declared owner remains the database owner across repeated provisioning
- **AND** the application login cannot create a role or assume the owner's identity
- **AND** neither login can authenticate to an unrelated consumer database

#### Scenario: Application login password rotates independently

- **WHEN** the additional login's declared password changes and provisioning runs again
- **THEN** the new password authenticates and the previous password is rejected
- **AND** the owner's password, database ownership and existing records remain unchanged

#### Scenario: Existing consumer declares no additional logins

- **WHEN** an existing consumer is provisioned without additional login registrations
- **THEN** its current ownership, authentication and backup behaviour remain unchanged

#### Scenario: Two consumers declare the same login name

- **WHEN** two consumers name the same login, as an owning role or an additional one
- **THEN** evaluation fails naming that login, because one role cannot carry two credentials or two sets of connection rules

### Requirement: PG-2 — Additional login credentials SHALL share the consumer's secret authority

Each additional login SHALL reference a consumer-owned encrypted password source that both the PostgreSQL substrate and application use. Provisioning SHALL establish all declared roles and credentials before the consumer's setup SQL runs. Recovery SHALL recreate additional logins from the same declarations without creating duplicate databases or exports for those roles.

#### Scenario: Consumer setup grants application access

- **WHEN** consumer setup SQL references a declared additional login
- **THEN** the role already exists with its declared credential
- **AND** the setup SQL can grant database-local permissions without the application receiving cluster administration privileges

#### Scenario: Database is restored on a replacement host

- **WHEN** the consumer's roles are provisioned and its logical export is restored
- **THEN** the owner and additional login can resume their respective operations with the declared credentials
- **AND** adding the application login has not introduced a second database ownership declaration or a duplicate database backup
