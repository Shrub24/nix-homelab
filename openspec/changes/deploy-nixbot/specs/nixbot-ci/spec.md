# Spec Delta

## Purpose

Provide nix-homelab's admitted CI builds, authenticated control and post-merge cache reconciliation without granting nixbot a deployment role.

## ADDED Requirements

### Requirement: NB-1 Explicit coordinator and repository admission

The fleet SHALL select one nixbot coordinator on home-forge. Discovery SHALL admit only `Shrub24/nix-homelab`, including when other repositories owned by Shrub24 are visible to its App. Stock PR approval SHALL admit in-repository branches and hold untrusted fork PRs for authorized Approve CI. No custom owner-PR admission patch SHALL be required.

#### Scenario: Discovery includes sibling repositories

- **WHEN** the App discovers homelab, another Shrub24 repository and a foreign repository
- **THEN** only homelab is admitted by the effective configuration

#### Scenario: Fork approval

- **WHEN** an untrusted fork PR arrives
- **THEN** its build waits for Approve CI and starts after authorized approval

### Requirement: NB-2 Whole-hostname application authentication

Native GitHub OAuth SHALL authorize UI control, private visibility and explicit administrators. Public projects MAY be anonymously readable. Cloudflare Access SHALL be disabled for the entire hostname; proxy identity and unauthenticated control SHALL be disabled. Webhooks SHALL require valid signatures.

#### Scenario: Anonymous control and forged delivery

- **WHEN** anonymous control, a spoofed username header or an invalid webhook signature is presented
- **THEN** it grants neither control nor build scheduling

### Requirement: NB-3 Complete checks and multi-architecture builds

Every validation formerly performed by the Actions contract job SHALL be represented in buildable checks, alongside formatting, generated-flake/dependency freshness, host toplevels and package retention roots. Nixbot SHALL evaluate with IFD disabled using two workers at 3072 MiB and build admitted checks on canonical x86 and ARM fleet capacity. Build inputs SHALL contain no service credentials.

#### Scenario: Complete verdict

- **WHEN** an admitted PR builds
- **THEN** nixbot/nix-eval and nixbot/nix-build cover the complete verdict, including contracts and both architectures
- **AND** ARM execution is evidenced on the builder, not inferred from substitution

### Requirement: NB-4 Main cache reconciliation and repair

Main's cache-retain effect SHALL depend on both architecture roots, push each before creating its rolling pin, use the cache lock and fail visibly on publication failure. It SHALL use workload identity with the declared cache audience and an explicit empty secrets map. Restart SHALL rerun push/pin repair without changed-input skipping. PR effects SHALL remain disabled.

#### Scenario: Main after an equal-tree merge

- **WHEN** main reuses a built PR tree
- **THEN** cache-retain still runs and both nix-homelab-main-<system> pins reference the new roots

#### Scenario: Outage and repair

- **WHEN** cache-retain is restarted with niks3 stopped and then restarted after recovery
- **THEN** the first run fails visibly and the second pushes and pins successfully

### Requirement: NB-5 Publication authority is explicit

The warn-only uploader MAY retain the accepted static admin token; its pin authority and shared revocation SHALL be documented. Normal main pinning SHALL use an exact repository/main/push/effect-bound OIDC rule with write scope and only the homelab rolling pin namespace. Actual token shapes and negative-token rejection SHALL be observed before accepting this trust path.

#### Scenario: Other identities denied

- **WHEN** an actual PR token or another effect's token reaches niks3
- **THEN** it cannot publish or pin through the main reconciliation rule

### Requirement: NB-6 Recoverable state and honest downtime evidence

The coordinator SHALL use the existing PostgreSQL substrate, consistent database exports, private state backup and failure notifications. Lost webhook deliveries SHALL NOT be claimed as replayed. Recovery SHALL use an observed rerun or subsequent push. Outage, token and downtime findings SHALL distinguish actual observations from expectations.

#### Scenario: Controller is stopped during a push

- **WHEN** nixbot is stopped, a push occurs and it restarts
- **THEN** the runbook records what was picked up, what was lost and the exercised recovery path

### Requirement: NB-7 Nixbot replaces CI and candidate authority

After observed acceptance, main SHALL require nixbot/nix-eval and nixbot/nix-build from its App integration with up-to-date branches and admin bypass. GitHub SHALL own merging: selected automation PRs auto-merge on green; human PRs await the operator. The candidate lifecycle and Actions CI/build/cache callers SHALL be retired. The scheduled producer SHALL remain until separately migrated.

#### Scenario: Merge policy

- **WHEN** checks are green, red or awaiting an operator
- **THEN** green automation may merge, red checks block a normal merge and human PRs are not automatically merged

### Requirement: NB-8 Deployment remains outside nixbot

Nixbot SHALL configure no deployment effect, deploy-tag trigger/ruleset, deploy credential, extra effects branches, event effects or per-repository effects secrets. Every effect SHALL declare an empty secrets map. Existing deployment workflows, tooling and still-used credentials SHALL remain.

#### Scenario: Ordinary CI or main reconciliation

- **WHEN** nixbot builds checks or pushes and pins artefacts
- **THEN** it activates no host and receives no deployment secret

### Requirement: NB-9 Staged observed retirement

Cache trust and coordinator activation SHALL precede an observed PR/merge/reuse/pin cycle and recovery experiments. App-sourced required checks SHALL precede deletion of old CI/candidate authority. No live task SHALL be completed by inference, and no merge SHALL occur without owner approval.

#### Scenario: A prerequisite is unavailable

- **WHEN** credentials, real token evidence or an observed cutover result is missing
- **THEN** that stage and dependent deletions remain pending in this change
