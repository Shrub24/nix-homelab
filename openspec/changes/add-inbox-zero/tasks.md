# Tasks

## 1. Policy and operator bootstrap (IZ-1, IZ-3, IZ-4)

- [x] 1.1 Add the verified tag/index digest to `policy/oci-images.nix` and a `direct` OCI route for `inbox.shrublab.xyz` in `policy/web-services.nix`; select an unused host port and keep Access/application OIDC off. Regenerate the existing web-policy export. Verify `tests/check-web-services-policy.sh` and `tests/check-web-service-catalog.sh` pass and the resolved provider/port match the planned listener.
- [ ] 1.2 Add the OCI-and-owner SOPS rule, scope fixture and `secrets/.templates/services/inbox-zero.yaml.j2` bootstrap inputs for the database, Google, auth/encryption, webhook, cron and internal credentials plus Gmail allowlist/topic. Write the secret-preparation and Google resource sections of `docs/runbooks/inbox-zero.md`. Verify `tests/check-secret-scope.sh`; operator creates the encrypted file before any host binding requires it. Do not create, read or edit plaintext secrets as an agent.

## 2. Application, database and AI wiring (IZ-1, IZ-2, IZ-4, IZ-6)

- [ ] 2.1 Add the discovered `modules/apps/inbox-zero.nix` owner with the bridged container, loopback-only publication, fleet service-address mapping, rendered environment and required-value startup validation. Register its dedicated SCRAM database consumer and extension setup through `modules/database/postgres/_consumer.nix`; order the unit after successful provisioning. Select the aspect and bind the secret in the OCI host record/private composition. Verify OCI `system.build.toplevel.drvPath` evaluates after `git add -A`, without building a host closure; verify the role has no superuser grant and its allowed CIDRs are app-scoped.
- [ ] 2.2 Wire `openai-compatible` to the colocated container-reachable Bifrost origin with `/v1` appended once and the fleet text alias. Land only missing focused evaluated relationship checks, extending `tests/check-user-app-placements.sh` where appropriate; do not grep production source or copy whole configuration inventories. Verify listener/route agreement, DSN/provisioning credential identity, private gateway reachability and no placement on the other hosts. Update existing scaffold expectations only where this placement changes their owned assertions.
- [ ] 2.3 Complete runbook startup, migration-status, credential rotation and database recovery sections; record the decision and placement in existing architecture docs. Verify the rendered unit and environment semantics agree with the runbook, including no unnecessary state volume and database export ownership. Keep legal guidance qualified and best-effort ingestion explicit.

## 3. Authenticated maintenance (IZ-3, IZ-6)

- [ ] 3.1 Add local watch-renewal and scheduled-action oneshots/timers at six hours and one minute, with credential-backed bearer headers, failure-sensitive HTTP and existing failure notification registration. Document the tagged Compose cadence discrepancy. Verify the evaluated timers use the placing app's loopback port and credentials are absent from command arguments; execute the rendered request wrapper against a non-secret local success/error fixture to confirm HTTP errors fail the unit command.
- [ ] 3.2 Inspect rendered Caddy configuration and relevant app logging settings for webhook query-token disclosure; preserve disabled request logging or redact secrets wherever logs are enabled. Document Cloudflare/Google log controls and wrapped subscription setup. Verify invalid-token rejection in runtime acceptance rather than duplicating upstream authentication algorithms in tests.

## 4. Integration and live acceptance

- [ ] 4.1 Parent runs `treefmt --fail-on-change`, `just checks all`, `tests/check-dendritic-scaffold-contract.sh` and `openspec validate add-inbox-zero --strict`. Confirm all declared host toplevel derivations instantiate; keep fleet builds out of routine CI. Resolve accepted bounded-review findings before overlapping edits.
- [ ] 4.2 With operator authorization and prepared Google resources/secrets, deploy OCI and verify provisioning, extension availability and actual Prisma migration status. Verify allowlisted Google sign-in and rejection of an unlisted account. Record consent/publishing mode and Testing's seven-day expiry caveat; do not mark unattended acceptance complete while credentials are knowingly short-lived.
- [ ] 4.3 Verify a missing/wrong webhook token is rejected and a valid wrapped delivery reaches a controlled Gmail rule. Verify watch registration/renewal and scheduled-action calls; exercise a representative app-generated structured Bifrost request and its schema-conforming result. Record actual results and any remaining upstream best-effort limitations in the runbook; ordinary chat or HTTP acknowledgement is not sufficient.

## Workflow follow-up

- Archive the change and sync its spec before merging the implementation PR, after review and the agreed acceptance gates. Do not mark live tasks complete on evaluation evidence alone.
