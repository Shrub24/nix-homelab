## ADDED Requirements

### Requirement: VE-1 Voyage embedding requests SHALL be normalized at the provider boundary
The gateway SHALL omit `encoding_format` when its value is `float`, preserve `base64`, and translate `dimensions` to `output_dimension` for Voyage embeddings only, while preserving other fields. Normalization SHALL be performed by a gateway plugin loaded from nix-fleet's Voyage plugin package; this repository SHALL NOT reimplement, wrap, or duplicate the transformation in another artifact.

#### Scenario: Docs-mcp requests floating-point embeddings
- **WHEN** docs-mcp requests `voyage/voyage-4` with `encoding_format: "float"`
- **THEN** Voyage receives the same input and model without that field
- **AND** the client receives floating-point vectors in the provider's response

#### Scenario: A client requests base64 embeddings
- **WHEN** a Voyage embedding request contains `encoding_format: "base64"`
- **THEN** the encoding field and response representation remain unchanged

#### Scenario: A client requests an explicit dimension
- **WHEN** a Voyage embedding request contains `dimensions` and no native `output_dimension`
- **THEN** the provider receives `output_dimension` with that value instead

#### Scenario: A different provider or operation is requested
- **WHEN** a request targets chat, reranking, or a provider other than Voyage
- **THEN** it does not pass through the Voyage embedding plugin

### Requirement: VE-2 The gateway SHALL load the plugin from a published, matched nix-fleet revision
The gateway runtime SHALL consume nix-fleet's Bifrost package and its Voyage plugin package from a single published nix-fleet revision, and SHALL declare the plugin through the gateway module's plugin registry, which owns the `plugins` member of the configuration document. A path override, local checkout, or unpublished revision SHALL NOT be committed as the consumed pin. The plugin entry SHALL name `voyage-normalizer`, point at the plugin package's `lib/bifrost/voyage.so`, and use `post_builtin` placement, and the rendered effective configuration SHALL be the artifact installed into the runtime directory. The consuming runtime SHALL be nix-fleet's Bifrost binary, and the configuration document SHALL be valid for that binary's schema, including declaring the gateway's admin account through the binary's own authentication configuration.

#### Scenario: The gateway configuration is rendered
- **WHEN** the gateway service renders its effective configuration
- **THEN** it contains one plugin entry with the plugin package's `voyage.so` path, the name `voyage-normalizer`, and `post_builtin` placement
- **AND** the Voyage upstream, the routing rules, and the existing `otel` plugin entry are preserved

#### Scenario: The pinned revision does not expose the packages
- **WHEN** the consumed nix-fleet revision lacks the Bifrost or Voyage plugin package output for the host system
- **THEN** the change stops rather than substituting a local override or an unpublished revision

### Requirement: VE-3 The plugin boundary SHALL remain private, in-process, and stateless
The plugin SHALL load into the existing gateway process, add no listener, proxy, sidecar, or middleware daemon, and create no persistent state, new secret binding, or expanded secret readership. Provider authorization SHALL remain the existing provider key binding and per-provider `extra_headers`. The plugin's changes SHALL reach the fixed HTTPS Voyage embedding upstream only.

#### Scenario: The plugin is active
- **WHEN** the gateway serves a Voyage embedding request to the plugin
- **THEN** normalization happens in-process and the provider receives the existing provider authorization
- **AND** no additional process, port, or secret file exists for normalization

### Requirement: VE-4 Compatibility SHALL preserve consumer and store identity
The compatibility change SHALL retain downstream URLs, `voyage/voyage-4`, existing 1024-dimensional store metadata, and stored vectors. It SHALL NOT require a reindex, model migration, new client credentials, or expanded secret readership. Upstream response bytes, status codes, content type, and retry information SHALL be preserved, and an upstream failure SHALL NOT be converted into success.

#### Scenario: Existing documentation is queried after the fix
- **WHEN** an existing docs-mcp index is queried through its unchanged configuration
- **THEN** its query embedding succeeds and existing vectors remain usable

#### Scenario: Voyage rejects a request or rate-limits it
- **WHEN** Voyage returns HTTP 400 or 429
- **THEN** the gateway preserves that status and response body
- **AND** forwards any upstream retry timing

#### Scenario: A failed page is retried
- **WHEN** the failed `https://pi.dev/docs/latest` page is retried after the fix
- **THEN** its chunks are embedded into the existing store without resetting that store

### Requirement: VE-5 The plugin mechanism SHALL be proven on the host's architecture before deployment
Because upstream live-load evidence exists only for `x86_64`, the change SHALL produce `aarch64-linux` build and live plugin-load evidence through a real embedding request before any deployment, and SHALL NOT treat `x86_64` evidence or evaluation-only output-path checks as satisfying this gate.

#### Scenario: Deployment is proposed for the aarch64 host
- **WHEN** the gateway with the Voyage plugin is about to be deployed to `aarch64-linux`
- **THEN** a recorded `aarch64` live load and normalization result exists for the evaluated revision

## Constraints

- These behaviors extend `openspec/specs/ai-gateway/spec.md` without changing its unrelated requirements.
- Compatibility is local to the selected gateway capability; it introduces no public endpoint, host-placement change, or index-data migration.
