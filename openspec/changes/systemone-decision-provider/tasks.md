# Tasks

## 1. Gateway providers

- [x] 1.1 Register `command-code` (custom OpenAI format) and `command-code-decisions`
  (custom TypeSafe format, decisions only, pinned `typesafe/jev-1.14.0`) in
  `policy/bifrost-config.json`, both on `https://api.commandcode.ai/provider` and both
  reading `env.COMMAND_CODE_API_KEY`; render that variable from
  `bifrost/command_code_api_key` in `modules/ai/bifrost.nix` and add the key to the
  secret bootstrap template. Verify both Bifrost hosts evaluate and the rendered
  configuration carries the two entries.

## 2. Decision consumer

- [x] 2.1 Point Inbox Zero's `DEFAULT_DECISION_MODEL` at
  `systemone-compatible:command-code-decisions/typesafe/jev-1.14.0` and set
  `SYSTEMONE_COMPATIBLE_URL` from the gateway's container base URL on the native
  System One route; leave the generative alias and the AI Gateway credential binding
  untouched. Verify the rendered container environment.

## 3. Documentation

- [x] 3.1 Record the provider pair, the credential step and the decision route in
  `docs/runbooks/bifrost.md` and `docs/runbooks/inbox-zero.md`, and name the new
  upstream in `docs/privacy.md`.

## 4. Left to the operator

- [ ] 4.1 Add `command_code_api_key` to `secrets/services/bifrost.yaml` and confirm the
  plan tier and terms cover decision traffic. An absent key fails activation.
- [ ] 4.2 Deploy deliberately: gateway hosts first, then Inbox Zero; exercise a synthetic
  decision and confirm the upstream served it rather than the LLM fallback.
