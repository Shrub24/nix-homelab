# Proposal

## Why

The Inbox Zero fork carries a System One-compatible decision provider
(`DEFAULT_DECISION_MODEL=systemone-compatible:<model>` plus a full endpoint URL),
and the fleet's gateway already speaks TypeSafe's System One API. The fleet needs
Command Code registered as a provider so both capabilities can be tried against a
real upstream — ordinary chat completions and typed decisions — and so the fork's
compatible provider can be exercised end to end rather than reviewed.

**Core Value:** one credential, one upstream, both model families reachable through
the gateway, with the decision route proven against the pinned gateway build before
anything is deployed.

## What Changes

- Register Command Code twice in Bifrost's policy: `command-code` as a custom
  OpenAI-format provider for chat completions, and `command-code-decisions` as a
  custom TypeSafe-format provider that allows only decisions. Both read one service
  secret, `bifrost/command_code_api_key`, rendered as `COMMAND_CODE_API_KEY`.
- Point Inbox Zero's decision model at the gateway's native System One route:
  `DEFAULT_DECISION_MODEL=systemone-compatible:command-code-decisions/typesafe/jev-1.14.0`
  and `SYSTEMONE_COMPATIBLE_URL=<gateway>/typesafe/v1/systemone`.
- Update the privacy disclosure, the gateway runbook and the Inbox Zero runbook:
  decisions no longer leave through AI Gateway's Perplexity path, and the upstream
  that now sees classification content is named.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `ai-gateway`: adds the Command Code provider pair, the shared credential boundary,
  and the requirement that a decision consumer names the gateway's System One route
  and the provider-prefixed model.

## Impact

`policy/bifrost-config.json`, `modules/ai/bifrost.nix` (environment and secret
binding), `secrets/.templates/services/bifrost.yaml.j2`, `modules/apps/inbox-zero.nix`,
`docs/runbooks/bifrost.md`, `docs/runbooks/inbox-zero.md`, `docs/privacy.md`.

Encrypted secrets are not read or edited: the operator adds the Command Code key to
`secrets/services/bifrost.yaml`. No deployment, no other service's route and no
Inbox Zero generative work changes — the `inbox-zero-text` alias keeps its Merge
route. The operator must confirm Command Code's plan tier covers the decision model
and that its terms permit the email content the route sends.
