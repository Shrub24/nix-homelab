## ADDED Requirements

### Requirement: Identity-host migration SHALL preserve the canonical Kanidm state
When the designated Kanidm host is replaced, the replacement SHALL restore the canonical identity state and retain the existing declarative OIDC client topology and encrypted client credentials before it receives public identity traffic.

#### Scenario: LA becomes the identity host
- **WHEN** `la-admin-1` is prepared to replace the existing Kanidm host
- **THEN** Kanidm backup recovery and OIDC client validation complete before the Cloudflare origin endpoint changes
- **AND** existing consumer callback URLs and client secrets remain valid through the transition

### Requirement: Kanidm replacement SHALL restore portable state before service authority
The replacement SHALL use the version-matched Kanidm portable backup export as the authoritative restore input. A source-controlled helper SHALL restore and verify the export while `kanidm.service` is stopped; only then may the service start and reconcile its unchanged declarative provisioning inputs. The helper SHALL treat every nonzero offline verification result as fatal before ownership repair or service start, with the verifier's output surfaced for diagnosis. It SHALL otherwise accept a verification only when it exits zero, carries its clean-success marker, and reports no error-bearing output. Routine non-error startup and reindex diagnostics MAY be present only on that clean path, but inconsistent clean output and temporary verifier-output leakage SHALL remain fatal defects.

#### Scenario: LA restores Kanidm before first start
- **WHEN** LA receives a staged or final Kanidm backup artifact
- **THEN** its stopped restore helper performs offline restore and verification
- **AND** any nonzero or error-bearing verification result remains fatal before ownership repair or service start
- **AND** the service does not create or provision a fresh authoritative database before that restore

### Requirement: Kanidm target readiness SHALL be independent of the public edge

Before public cutover, Kanidm provisioning and its startup readiness check SHALL connect to the local loopback server endpoint using the upstream `https://localhost:<bind-port>` default. The target SHALL NOT require Cloudflare DNS, Authenticated Origin Pull client credentials, or a public-edge TLS route to start and reconcile restored declarative inputs.

#### Scenario: LA starts after private restore before DNS cutover

- **WHEN** the restored LA Kanidm service starts while public DNS still resolves to DO
- **THEN** local provision readiness reaches LA's loopback Kanidm listener without contacting the public route

## REMOVED Requirements

### Requirement: Kanidm restore SHALL tolerate only the proven v1.10.4 revoked-session verifier false positive

Superseded by `openspec/changes/kanidm-1-11-upgrade`: the v1.10.4 exception predicate was migration-window residue, removed with the Kanidm 1.11 upgrade. The restore helper is now unconditionally fail-closed with no acceptance path. This requirement is removed from this change's delta so archiving it cannot resurrect the exception contract.
