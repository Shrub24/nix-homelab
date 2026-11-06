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
