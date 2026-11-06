# Tasks

## 1. Inbox Zero decisions

- [x] 1.1 Upgrade the published image pin, wire AI Gateway's Perplexity Decider with both enable flags and an isolated required SOPS credential, update its bootstrap template, privacy policy and runbook. Verify OCI host evaluation, rendered secret-to-environment identity and the real startup validator with non-secret complete/missing/empty credential fixtures; check privacy-page HTTP behaviour. Do not deploy or claim live inference.

## 2. Merge Gateway

- [x] 2.1 Register the OpenAI-compatible Merge provider and shared Bifrost SOPS environment binding, extend the bootstrap template and document operator setup. Route Inbox Zero's LLM alias to `deepseek/deepseek-v4.1-flash-1017` without cross-provider fallback; preserve other services' routes. Verify both Bifrost-placing hosts evaluate, the custom-provider configuration matches upstream schema, and the rendered key binding reaches the configured provider; existing Bifrost integration checks must pass.

## 3. Integration

- [x] 3.1 Run focused application, secret-scope, public-page and formatting checks plus strict OpenSpec validation; review the bounded diff for credential leakage and unrelated changes. Report operator secret entry, privacy-console settings, database export and deployment acceptance as outstanding operator actions, not completed runtime checks.
