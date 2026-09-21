## Context

The flake update moves Paperless-ngx from 2.20.15 to 3.0.4. The upstream service units receive the configured `environmentFile`, but the local `paperless-group-seed` systemd unit runs Django without it. Paperless v3 requires `PAPERLESS_SECRET_KEY` for every Django startup.

The v3 migration guide also changes duplicate handling to accept duplicates by default. This fleet previously relied on the v2 rejection default.

## Goals / Non-Goals

**Goals:**

- Keep every local Paperless Django process on the same sealed runtime environment contract.
- Preserve v2 duplicate-rejection behavior explicitly.
- Validate the generated unit rather than relying on a live activation failure.

**Non-Goals:**

- Modify secret contents or SOPS recipients.
- Run document decryption; the document store has no encrypted documents.
- Configure conditional v3 settings without evidence of the associated failure.

## Decisions

- **Use `services.paperless.environmentFile` for the group seeder.** This is the declared runtime contract already consumed by upstream Paperless units. Referencing it keeps custom maintenance units aligned if the environment source is overridden later. Referencing the SOPS template directly would duplicate that binding.
- **Set `PAPERLESS_CONSUMER_DELETE_DUPLICATES=true`.** v3 otherwise reverses the v2 default. An explicit setting preserves existing and future ingest semantics.
- **Apply only migration-guide actions that are relevant.** The current configuration already sets `PAPERLESS_SECRET_KEY` and `PAPERLESS_DBENGINE=postgresql`; it has no removed consumer, barcode, database, or OCR environment settings, and the post-consume hook already uses environment variables. Tantivy index rebuilding and database migrations are upstream automatic actions. OIDC token-authentication and trusted-proxy settings remain conditional on `invalid_client` and login-rate-limit failures respectively.

## Risks / Trade-offs

- **A future upstream environment-file type change** → Evaluate the rendered custom unit with the host configuration before deployment.
- **Duplicate rejection may discard an intentional re-import** → This matches v2 behavior; an operator can disable the explicit setting later if the policy changes.
- **Unobserved OIDC proxy or token-auth changes** → Verify OIDC login after deployment and only configure the documented conditional settings if their errors occur.

## Migration Plan

1. Evaluate the host configuration to confirm the custom unit loads the configured Paperless environment file and the duplicate-rejection setting is present.
2. Deploy through the normal host workflow.
3. Confirm `paperless-group-seed.service` succeeds and OIDC login works.
4. Roll back through deploy-rs if activation or login fails.
