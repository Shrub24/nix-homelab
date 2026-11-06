# Design

## Context

See proposal.md. The current image is release 2.30.0; decisions arrived later. Published commit `82004cd7aac1dc2de7f1ebcdb8afe1df96f80af3` has amd64 and arm64 manifests under index `sha256:182ca110030c6505e74d67d996deb46f4a5424f57263b222745cc26bd5571a97`.

## Goals / Non-Goals

Use existing aspect-owned environments and SOPS bindings. Do not patch upstream, create a proxy, change other services' Bifrost routes, deploy, or modify encrypted secrets.

## Decisions

### IDM-1 Dedicated decision credential

Set `DEFAULT_DECISION_MODEL=aigateway:perplexity/pplx-decider-v1.2`, both enable flags true, and render `AI_GATEWAY_API_KEY` from `inbox-zero/ai_gateway_api_key`. Require it at unit start. Do not use shared `LLM_API_KEY`, which could leak this credential to Bifrost. Keep the upstream user opt-out and personal-key semantics.

### IDM-2 Published commit upgrade

Pin commit tag plus multi-architecture digest rather than mutable latest; the latest server release lacks the feature. There are 96 added migration directories and none removed relative to the old source, so this is a real database upgrade, not merely environment changes. The app still starts after migration failure; require independent live acceptance. Native database export remains the recovery mechanism.

### IDM-3 Explicit provider policy

Replace ZDR-only wording with no-training and retention disclosure. AI Gateway is a separate external hop for decisions; Bifrost remains the LLM/fallback path. No-training controls, agreements and the complete fallback chain require operator verification. Current Inbox Zero decision calls do not supply the gateway's per-request no-training filter; document that limitation instead of asserting enforcement. Cold-email opt-in is explicit despite upstream's accuracy-driven default-off choice (PR #4162).

### IDM-4 Merge wire format

Register `merge-gateway` with Bifrost's existing custom OpenAI-provider mechanism, base `https://api-gateway.merge.dev/v1/openai`, and `MERGE_GATEWAY_API_KEY` from `bifrost/merge_gateway_api_key`. The native `/v1/responses` has a different response shape; the explicit OpenAI prefix avoids that ambiguity. Only the new `inbox-zero-text` alias selects Merge's `deepseek/deepseek-v4.1-flash-1017`, without cross-provider fallback; other aliases are unchanged. The operator confirmed Merge's upstream ZDR restrictions. Every host placing Bifrost consumes the shared service secret.

## Risks / Trade-offs

- Forward migrations → operator exports the database before deploying; generation rollback does not reverse SQL.
- Missing new SOPS entries → operator adds them before deployment; fail closed, never generate real provider credentials.
- Decisions fall back to general LLM routes → operator checks no-training terms for the entire chain.
- Cold-email false negatives → exercise nuanced unsolicited pitches before unattended acceptance.

## Migration Plan

Populate both new encrypted keys, configure provider privacy controls and disclose processing to users. Export Inbox Zero's database, deploy OCI deliberately, verify Prisma migrations and synthetic decision inference, then test a controlled mailbox task. Deploy shared Bifrost policy to other placing hosts separately. On failure stop processing; restore the pre-upgrade database with the old image if needed.
