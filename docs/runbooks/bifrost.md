# Bifrost provider credentials

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
