# Design

## Context

Command Code's Provider API serves both families the route needs on one base URL,
`https://api.commandcode.ai/provider/v1`: OpenAI chat completions on
`/chat/completions`, and TypeSafe's System One decision API on `/systemone` with
models `typesafe/jev` and the pinned `typesafe/jev-1.14.0`. One account key
authorises both.

The pinned gateway build is Bifrost 2.3.0. Its transport tree registers the native
`/typesafe/v1/systemone` route (`bifrost-http/integrations/typesafe.go`), accepts
`typesafe` as a custom-provider base format, and carries the decision request in
`handlers/inference.go`. The provider/model/model-format configuration below was
therefore proven against that exact build rather than against current documentation,
by running the 2.3.0 binary against a mock upstream that recorded what reached it.

## Goals / Non-Goals

Two provider registrations over one credential, one consumer routed through the
gateway, and a contract check that fails when either half drifts. Not in scope:
changing other services' routes or aliases, provider fallback chains, embeddings
through Command Code, Anthropic's Messages surface, or any deployment.

## Decisions

### CCD-1 One upstream, two provider entries

Bifrost selects a base format per provider entry, so a single entry cannot serve
both an OpenAI operation and a decision. `command-code` is registered as a custom
`openai` provider and `command-code-decisions` as a custom `typesafe` provider, both
pointing at the same upstream and reading the same `COMMAND_CODE_API_KEY`. The
decision entry sets `allowed_requests.decisions` only, so the decision provider
cannot be reached for chat work and a misrouted call fails before an upstream call.
The chat entry leaves `allowed_requests` unset: absent means every operation the base
format supports, which is what a general chat provider should offer.

### CCD-2 Base URL stops at the provider prefix

Bifrost appends its own `/v1/<operation>` to `network_config.base_url`. With
`.../provider/v1` the observed chat request reached the upstream as
`/provider/v1/v1/chat/completions`; with `.../provider` it arrived as
`/provider/v1/chat/completions`. The base URL therefore stops after `provider` and
no `request_path_overrides` entry is needed for either family — verified for both
`/v1/chat/completions` and `/v1/systemone`.

**Rejected:** a full-URL `request_path_overrides` entry per operation. It also
worked, but each override is a second copy of a path Bifrost already composes, and it
would have to be repeated for every operation the chat provider serves.

### CCD-3 The consumer names the provider prefix, and Command Code's vendor prefix survives

Bifrost strips one leading path segment from the model, resolving the rest inside the
named provider. The consumer therefore sends
`command-code-decisions/typesafe/jev-1.14.0`; the upstream observed a body model of
`typesafe/jev-1.14.0`, which is what Command Code documents. The bare form
`typesafe/jev-1.14.0` on the native route fails with
`failed to get config for provider typesafe: not found` — the vendor prefix is not a
provider name, and Inbox Zero cannot send the short form.

### CCD-4 Pinned release, moving alias unwelcome

The decision key admits only `typesafe/jev-1.14.0`. The `typesafe/jev` alias answers
the same endpoint today and may move; a comparison that changes model under the
tester cannot separate the fork's implementation from the model's behaviour.

### CCD-5 One credential, no client credential

Both entries read `env.COMMAND_CODE_API_KEY`, rendered from the existing
`services/bifrost.yaml` service scope, so a consuming host never holds a Command Code
key and a rotation is one file. The consumer sends no credential: the fork resolves
this provider's key from `SYSTEMONE_COMPATIBLE_API_KEY` alone and never from
`LLM_API_KEY`, so leaving it unset keeps an unrelated LLM key off the decision route,
and the gateway authenticates no in-fleet client.

### CCD-6 The decision route is exercised, not reserved

Inbox Zero's `DEFAULT_DECISION_MODEL` moves from `aigateway:perplexity/pplx-decider-v1.2`
to the compatible provider, because a route nobody calls proves nothing about the
fork's implementation. The AI Gateway credential binding stays in place — it is the
neighbouring change's documented fallback path for generative work — so this change
is one setting plus one endpoint and reverts by restoring one line.

## Risks / Trade-offs

- **The disclosure must move with the route.** `docs/privacy.md` names AI Gateway and
  Perplexity for classification content; the operator must publish the Command Code
  disclosure before live mail processing, and confirm the plan tier and terms cover
  decision traffic.
- **A decision model id is not an entitlement.** Command Code gates Jev at its GOAT
  plan; an account without it fails at the upstream, not at evaluation.
- **The route sends email content to a new upstream.** This is the same class of hop
  as the one it replaces, but a different provider and therefore a different
  agreement.
- **One generation's rollback does not undo the endpoint change.** Reverting the
  setting is a code change, not a runtime switch.
- **Observed in passing, unchanged here:** a fresh gateway deployment resolves
  omitted `client.enforce_auth_on_inference` to true and refuses keyless inference,
  so the local experiment set it false explicitly. The fleet's rendered policy does
  not set it; its deployed value lives in the gateway's config store and this change
  neither reads nor alters it.

## Migration Plan

1. Operator adds `command_code_api_key` under the existing `bifrost` mapping of
   `secrets/services/bifrost.yaml` and re-encrypts to both gateway hosts. An absent
   key fails activation, so this precedes any deploy.
2. Deploy a gateway host deliberately; confirm the provider list carries both
   entries and `bifrost.service` is healthy.
3. Send a synthetic decision through the native route and a synthetic chat
   completion, confirming Command Code reports `typesafe/jev-1.14.0` and the chat
   model respectively.
4. Deploy Inbox Zero; exercise one synthetic mailbox decision and confirm the
   gateway logged the decision route for that request.
5. If the fork's implementation proves unusable, restore the previous
   `DEFAULT_DECISION_MODEL`; the providers and the credential stay available.
