# Bifrost provider credentials

## Add Command Code

Command Code serves the fleet twice from one upstream, `https://api.commandcode.ai/provider`:
chat completions through the `command-code` custom provider, and typed decisions through
`command-code-decisions`, a custom provider on Bifrost's TypeSafe base type that admits only
the decision request type.

1. Open the existing encrypted service file as the operator and add
   `command_code_api_key` under the existing `bifrost` mapping. Do not re-bootstrap
   the file or rotate unrelated credentials.

   ```sh
   sops secrets/services/bifrost.yaml
   ```

2. Confirm the account's plan covers the decision model and that its terms permit the
   content the route carries. Decisions are gated on Command Code's upper tiers; an
   account without them fails at the upstream, not at evaluation.

3. Deploy the Bifrost-placing hosts deliberately. Confirm the gateway starts and lists
   both providers. Do not print the rendered environment or the key.

4. Send a synthetic decision to the native route, naming the provider and Command
   Code's vendor prefix, and confirm the answers come back and that Command Code's
   usage metadata shows `typesafe/jev-1.14.0`:

   ```sh
   curl -sS localhost:7411/typesafe/v1/systemone -H 'Content-Type: application/json' \
     -d '{"model":"command-code-decisions/typesafe/jev-1.14.0","state":"probe",
          "questions":{"q":{"type":"noul","instructions":"Is this a probe?"}}}'
   ```

5. Send a synthetic chat completion naming `command-code/<model>` and confirm Command
   Code reports the model.

The base URL stops after `provider` because the gateway appends its own `/v1/<operation>`.
Bifrost strips one path segment from the model to pick the provider, so the consumer keeps
Command Code's vendor prefix and the gateway forwards `typesafe/jev-1.14.0` unchanged.
Anthropic models on this upstream are served on `/messages`, not chat completions.

To stop using it, remove the routes naming these providers before removing the provider
entries or the credential.

## Add Merge Gateway

1. Open the existing encrypted service file as the operator:

   ```sh
   sops secrets/services/bifrost.yaml
   ```

   Add `merge_gateway_api_key` under the existing `bifrost` mapping. Do not
   re-bootstrap the file or rotate unrelated credentials. The file is shared by
   the Bifrost instances on `oci-melb-1` and `home-forge`.

2. Check the Merge console's upstream provider selection, privacy controls and
   available model IDs before using the credential for email processing. The
   policy routes only `inbox-zero-text` to Merge's
   `deepseek/deepseek-v4.1-flash-1017`, with no cross-provider fallback. Existing
   fleet aliases keep their previous routes.

3. Deploy the Bifrost-placing hosts deliberately. Confirm `bifrost.service` starts
   successfully on each and lists the `merge-gateway` custom provider. Do not
   print the rendered environment or API key.

4. Send a synthetic request using the `inbox-zero-text` alias. Verify a successful response and the selected upstream in
   Merge's usage metadata. Check any desired streaming or structured-output mode
   before assigning a production route.

The provider uses `https://api-gateway.merge.dev/v1/openai`, which Merge documents
for OpenAI-compatible Chat Completions and Responses. Its native `/v1/responses`
uses a different response shape. Do not substitute that native endpoint for the
OpenAI-compatible base URL merely because both return successful HTTP responses.
See [Merge's SDK setup](https://docs.merge.dev/merge-gateway/get-started) and
[native Responses reference](https://docs.merge.dev/merge-gateway/api-overview/responses/create).

To stop routing through Merge, remove any routes you subsequently assign before
removing the provider or its secret. Inbox Zero uses this route for generative
work and fallback after a decision error; Perplexity Decider still handles supported
decision tasks through AI Gateway.

## Add Neuralwatt

1. Open `secrets/services/bifrost.yaml` with SOPS and add `neuralwatt_api_key`
   under the existing `bifrost` mapping. Do not re-bootstrap the file or rotate
   unrelated keys. This service-scoped credential is consumed by both
   `oci-melb-1` and `home-forge`.
2. Deploy the Bifrost-placing hosts deliberately. Confirm the gateway starts with
   the `neuralwatt` custom provider at `https://api.neuralwatt.com/v1` without
   printing the rendered environment or credential.
3. Send a synthetic Chat Completions request using `text-fast`; confirm Neuralwatt
   reports `deepseek-v4.1-flash` on the standard tier.
4. Send a synthetic **streaming** Chat Completions request using `text-flex`
   (`stream: true`); confirm Neuralwatt reports `deepseek-v4.1-flash-flex` and
   inspect the served tier and charged price in its usage metadata. Allow for
   delayed first-token admission. Non-streaming calls do not qualify for Flex
   pricing; even streaming requests may be served outside Flex under upstream's
   documented fallback conditions.

These aliases are standalone and have no cross-provider fallback. No existing
application or fleet alias moves to Neuralwatt. `text-fast` uses the standard
model, not Neuralwatt's separate energy-accounting-only Speed tier. Check provider
privacy terms before assigning sensitive production workloads; this addition
makes no Neuralwatt ZDR claim.

If reverting, stop any consumers you subsequently assign to these aliases before
removing the routes, provider or credential.

References: [API overview](https://docs.neuralwatt.com/api/overview),
[models](https://docs.neuralwatt.com/api/models), and
[Flex behaviour and pricing](https://docs.neuralwatt.com/guides/flex-tier).
