# Spec Delta

## ADDED Requirements

### Requirement: Asset sources SHALL be declared centrally

SA-1: Source choices SHALL be declared in repository policy. A source SHALL be either a tracked file, a local service path or an explicit upstream HTTPS URL. Service owners SHALL register their own runtime listener, ordering and refresh triggers independently of source policy. Registration without selecting publication SHALL evaluate without creating publication units.

#### Scenario: A curated icon is changed

- **WHEN** a tracked SVG is replaced
- **THEN** the next publication uses the new reviewed bytes without a fetch hash or updater recipe

#### Scenario: A service registers without a publisher

- **WHEN** its host does not select publication
- **THEN** registration evaluates and creates no publication units

### Requirement: Publication SHALL use independent runtime jobs

SA-2: Each registered asset SHALL have an independent publication job. A local source SHALL be read from the service host's supplied listener, without public-edge or Access dependencies, and SHALL wait only within a bounded window. File and explicit upstream sources SHALL not depend on local service readiness. Source or owning service changes SHALL refresh only the affected jobs. An operator SHALL be able to refresh one or all jobs explicitly.

#### Scenario: A local application is still starting

- **WHEN** its icon cannot yet be fetched
- **THEN** its job retries within a bounded window and fails without writing if the source remains unavailable
- **AND** other asset jobs are unaffected

#### Scenario: An operator refreshes all registered assets

- **WHEN** an explicit aggregate refresh is requested after successful publication
- **THEN** every registered job runs again, even if its previous successful unit is active

### Requirement: Publication SHALL preserve last-good content

SA-3: Publication SHALL validate candidate image bytes before upload, store an explicit image content type and cache policy, and skip writes when content and relevant metadata are unchanged. A failed read, invalid image or storage error SHALL leave previous content untouched. Publication SHALL NOT delete any object, including when a registration is withdrawn.

#### Scenario: A source returns an HTML login page with status 200

- **WHEN** the candidate is not an image
- **THEN** publication fails and the previously published object remains untouched

#### Scenario: An image is unchanged

- **WHEN** content and stored metadata match
- **THEN** publication performs no write

#### Scenario: An unrelated manual asset exists

- **WHEN** a job runs or a registration is withdrawn
- **THEN** the manual asset remains untouched

### Requirement: Managed assets SHALL use stable public addresses

SA-4: Managed assets SHALL use stable keys on the existing public R2 hostname, which SHALL stay outside web route policy and Access. Authentik SHALL use these addresses for all routed applications approved in the identity policy. External federation clients with no application route are excluded. Logo and favicon SHALL remain independently addressable. Manually uploaded raster branding SHALL remain outside publication.

#### Scenario: An application icon is published

- **WHEN** an unauthenticated viewer requests its asset URL
- **THEN** the image is available without an application or Access session

#### Scenario: A source format changes

- **WHEN** valid image content changes format
- **THEN** its key remains stable and its content type updates

### Requirement: Publication credentials SHALL remain runtime-only and bucket-scoped

SA-5: Publishing hosts SHALL use the existing shared credential from encrypted common secrets. Credential values SHALL not enter the Nix store. Authority SHALL be limited to reading and writing objects in the one public-content bucket, without account, bucket administration or other-bucket authority.

#### Scenario: Several hosts publish

- **WHEN** publication is selected on more than one host
- **THEN** each receives the same bucket-scoped runtime credential without duplicating secret values into source policy
