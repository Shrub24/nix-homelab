# Proposal

## Why

Deploy Inbox Zero for a personal Gmail account on `oci-melb-1`, using the fleet's existing database, gateway and ingress rather than another Compose-managed infrastructure stack. **Core Value:** a reproducible mail-assistant deployment with explicit authorization, recovery and operating limits.

## What Changes

- Publish a discovered `inbox-zero` application aspect running the official ARM64-capable image, initially version 2.30.0, pinned by tag and index digest.
- Register its database, role, credential, `uuid-ossp` and `btree_gist` setup through the native PostgreSQL consumer contract. Order startup after provisioning and verify migrations rather than trusting the image's startup warning handling.
- Publish `inbox.shrublab.xyz` as an OCI-local direct route. Google sign-in is the application gate; Cloudflare Access and application Kanidm OIDC are off. Restrict sign-up to the operator's Gmail address.
- Configure authenticated Google Pub/Sub push delivery, six-hour Gmail-watch renewal and one-minute scheduled-action timers. Use the internal queue without Redis or a worker; describe its best-effort delivery honestly.
- Route structured LLM requests through the colocated Bifrost container endpoint and the fleet text alias.
- Add service-scoped secret preparation, database recovery instructions, focused evaluated wiring checks and operator acceptance steps.

### Constraints

The target is `aarch64-linux`. Public webhooks are explicitly approved for this service; database and model traffic remain private. Operators own Google Cloud setup and encrypted secrets. No secret plaintext enters Git or the Nix store. Google External Testing's seven-day refresh-token expiry is not an unattended operating baseline. A successful container start is not proof of migrations, Gmail watches or AI compatibility.

## Capabilities

### New Capabilities

- `inbox-zero-service`: personal Gmail authorization, authenticated event delivery, local scheduled work, gateway use and recoverable native database state.

### Modified Capabilities

None. This deployment consumes the existing catalog, database and gateway boundaries. Related specs are `policy-service-catalog`, `postgres-shared-access`, `ai-gateway`, `secrets-management` and `state-backups`; some database wording predates the current consumer registry, so implementation follows the current mechanism rather than restoring retired options.

## Impact

Add `modules/apps/inbox-zero.nix`, route and image policy entries, OCI aspect selection and secret binding, `.sops.yaml` readership and a service secret template. Use the existing PostgreSQL substrate and its export-first backup. Extend focused contract validation and write an operator runbook. No fleet input changes, custom application build, Google infrastructure automation, Microsoft support, Kanidm adapter, Redis, worker, calendar/contacts/Drive integration or billing setup.

Source contracts and corrections are recorded in `docs/research/inbox-zero-deployment.md`. Upstream personal self-host guidance supports this plan; the commercial subtree's license interpretation is not settled by its inclusion in the image.
