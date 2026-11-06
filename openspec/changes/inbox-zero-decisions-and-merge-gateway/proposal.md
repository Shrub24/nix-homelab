# Proposal

## Why

Inbox Zero's pinned server release lacks the decision-model support the operator wants. The fleet also needs Merge Gateway registered as an available Bifrost provider. **Core Value:** make both integrations reproducible without changing other services' model routes or hiding operator prerequisites.

## What Changes

- Pin the published arm64-compatible Inbox Zero commit `82004cd` by index digest because the latest server release, 2.30.0, lacks decisions.
- Configure AI Gateway's `perplexity/pplx-decider-v1.2` as the decision default, enabled for eligible users and cold-email detection, with an app-scoped operator-provided credential.
- Keep ordinary LLM work and decision failures on Bifrost, using a dedicated `inbox-zero-text` alias to Merge Gateway's `deepseek/deepseek-v4.1-flash-1017`.
- Replace the privacy policy's strict ZDR commitment with no-training and accurate provider-retention disclosures, naming AI Gateway and Perplexity.
- Register Merge Gateway as a custom OpenAI-based Bifrost provider, using its OpenAI-compatible endpoint and an operator-provided credential. Other services' routing stays unchanged.

## Capabilities

### New Capabilities

- `inbox-zero-decisions`: default decision-model routing, credential boundary, privacy disclosure and upgrade acceptance.

### Modified Capabilities

None. Merge uses the existing `ai-gateway` provider-extension mechanism; the earlier `add-inbox-zero` change remains the deployment baseline. `secrets-management` and `state-backups` supply existing secret and recovery mechanisms.

## Impact

Changes affect the Inbox Zero image pin and module, Bifrost provider policy and secret binding, secret bootstrap templates, privacy page and operator documentation. No encrypted secrets are read or edited; no deployment, database migration, upstream app patch, new proxy or other services' routing change is included. Console-level no-training controls and provider agreements remain operator responsibilities; setting a model ID is not enforcement.
