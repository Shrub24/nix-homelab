# Design

## Context

See `proposal.md` for the motivation. The pinned docs-mcp 3.1.0 factory sets `encodingFormat: "float"` in its OpenAI branch, with no configuration override. It does **not** pass `dimensions`. Its separate store dimension remains 1024.

Source evidence: the live image's `dist/main-BDg2etpq.js:277–307` and `@langchain/openai` 1.5.5 request assembly at `dist/embeddings.js:77–78,101–102`. Read-only copies and the source report are referenced under Verification below.

Same-endpoint, same-model probes isolate two unsupported OpenAI fields: `encoding_format: "float"` returns 400; omitting it or requesting `base64` returns 200. Adding `dimensions: 1024` also returns 400, while `output_dimension: 1024` returns 200. The dimensions probes are compatibility tests, not a description of docs-mcp's actual request.

The developer's local nix-fleet checkout carries the mechanism this change consumes: a plugin-capable Bifrost derivation (`packages.<system>.bifrost`, `bin/bifrost-http`), a separate plugin derivation (`packages.<system>.bifrost-voyage-plugin`, `lib/bifrost/voyage.so`), and an offline check that loads the plugin through the real embedding route. The plugin exports `GetName() == "voyage-normalizer"` and a `PreLLMHook` that removes a float `encoding_format` and maps `dimensions` to `output_dimension` for the Voyage provider only. The prior `v1.5.0-prerelease8` image is a static build with no Go plugin loader and an older ABI; it cannot host this plugin. Upstream has exercised live plugin load on `x86_64` only.

## Goals / Non-Goals

**Goals:** Implement VE-1 through VE-4 by consuming the published nix-fleet Bifrost + plugin packages and declaring the plugin in the repo-owned gateway config, with an unchanged client/index contract.

**Non-Goals:** A general reverse proxy, a client fork, a Python/sidecar adapter, duplicated normalization inside this repository, new API credentials, a public listener, an image update, a model migration, backend relocation, or edits to nix-fleet. Existing divergences between the main gateway spec and D-076's configuration-store behavior are not part of this change.

## Decisions

### VE-1: Normalize on Bifrost's outbound Voyage embedding leg, inside a gateway plugin

```text
docs-mcp → unchanged Bifrost /v1/embeddings
         → in-process voyage-normalizer plugin (post_builtin)
         → https://api.voyageai.com/v1/embeddings
```

Normalization is owned by `bifrost-voyage-plugin`. The plugin removes a float `encoding_format` (Voyage's default response is already float vectors), preserves `base64`, maps a supplied `dimensions` to `output_dimension` when the client has not supplied `output_dimension` natively, and leaves non-Voyage providers untouched. This repository declares the plugin and never reimplements it.

The rejected alternatives stand: a client patch needs a maintained docs-mcp fork; a proxy before Bifrost moves provider knowledge into the caller boundary or affects unrelated providers; a second in-repo normalization helper would duplicate the plugin and create two owners for one transformation.

### VE-2: Consume the published packages and keep configuration ownership local

The gateway consumes `inputs.nix-fleet.packages.<system>.bifrost` and `inputs.nix-fleet.packages.<system>.bifrost-voyage-plugin`. They are separate derivations on purpose: the host executable and the plugin must share the Go toolchain, CGO setting, and vendored module graph so the runtime plugin loader's package hashes agree. Both come from one nix-fleet revision, so that agreement is a property of the pin rather than of this repository's build.

The pin is the published nix-fleet revision. `--override-input` / a local path may be used only for local evaluation and must not be committed as the consumed lock.

Keep the native Voyage endpoint in `policy/bifrost-config.json`, which stays the provider, routing and admin document — the module reads it as `services.bifrost.settings`. It carries no `plugins` member: the fleet's gateway module declares that member and refuses a second owner, so plugin registration happens where the fleet's schema puts it.

```nix
services.bifrost.plugins = {
  otel = { config = { /* the gateway's OTLP exporter */ }; };
  voyage-normalizer = {
    path = "${config.repo.packages.bifrost-voyage-plugin}/lib/bifrost/voyage.so";
    placement = "post_builtin";
  };
};
```

`placement: post_builtin` runs the hook after the built-in request pipeline, so the plugin observes the fully-assembled embedding request and its changes are what the provider receives. The `path` comes from the nix-fleet package output; no store path is hardcoded. The `otel` entry moves into the same registry, for the same reason it exists at all: it had been a member of the JSON document.

The runtime is nix-fleet's gateway service — the fleet module owns the unit, the application directory and the install of the rendered document — so this repository no longer derives a configuration revision of its own. What recreates the process is `restartTriggers`: the rendered document, which is content-addressed in the Nix store, plus the encrypted secret file, named explicitly because it sits at a stable path and systemd cannot see its content change. That is the D-077 failure mode, which a native unit shares and the `container-env` aspect does not cover. D-079 records the ownership move; the local unit and its input-derived `X-Bifrost-Config-Hash` were D-078's.

The runtime swap also requires `policy/bifrost-config.json` to be valid for 2.2.5, which changes the document beyond the plugin entry while preserving behaviour: the admin account moves to `auth_config` with env indirection because the binary no longer reads `BIFROST_ADMIN_USERNAME`/`_PASSWORD`, and `custom_provider_config` is removed from `deepseek` and `opencode-go`, which 2.2.5 treats as standard providers and rejects the block for, while its built-in base URLs already match ours. `voyage` remains a custom provider. "Preserved" therefore means the behaviour — the Voyage upstream, the routing rules, the `otel` entry — not byte identity of the document.

### VE-3: Keep the plugin in-process, private, and stateless

The plugin loads into the already-running gateway process in the gateway's host network namespace. It opens no listener, keeps no state directory, and reads no secret file. Provider authorization is unchanged: `env.VOYAGE_API_KEY` and per-provider `network_config.extra_headers` are the only credential surfaces, and this change adds neither.

Because there is no additional process, there is no new failure-notification contract, no new systemd unit ordering, and no loopback port. The existing gateway unit's start/stop covers the plugin.

### VE-4: Test the real boundary, not just a JSON helper

Normalization behavior is proven by nix-fleet's `checks.bifrost-voyage-plugin`, which starts the real `bifrost-http` binary with the plugin loaded and a mock provider recording the outbound bodies: Voyage float/dimensions normalized, explicit `output_dimension`/`base64` preserved, other providers untouched.

This repository's tests cover its own seam: the rendered Bifrost configuration contains exactly the expected plugin entry with the package-derived `voyage.so` path and `post_builtin` placement, and keeps the Voyage upstream and existing providers/routes intact. Any behavior assertion beyond that belongs to the plugin owner.

### VE-5: Gate `aarch64` load and live compatibility before deployment

Upstream's live load proof is `x86_64`-only, and the fleet's first host is `aarch64-linux`. Before deployment, the `aarch64-linux` artifacts must build and the plugin must actually load and normalize through a live embedding request on `aarch64` (or the fleet must accept the mechanism only after such proof). This is a release gate, not an implementation step: it is recorded as an explicit task with its own evidence, and it cannot be satisfied by `x86_64` evidence or by evaluation alone.

After the gate passes, exercise the pinned LangChain client with the **actual** factory arguments: `modelName: "voyage/voyage-4"`, `encodingFormat: "float"`, and no `dimensions`. Check document batches and query embeddings, then retry the failed page and query the existing index. Record vector count/dimension and outcomes, not vectors or document contents.

## Risks / Trade-offs

- Plugin ABI depends on toolchain, CGO, and vendored graph agreement → both derivations come from one nix-fleet revision that builds them with a shared builder; a pin that no longer satisfies this fails at load, which the plugin load gate detects before deployment.
- The mechanism is unproven on `aarch64` → VE-5 makes build-and-live-load proof an explicit blocking gate, not an assumption.
- A stale gateway generation could keep serving a configuration without the plugin → the unit's `restartTriggers` name the content-addressed rendered document and the encrypted secret file, and verification checks service recreation, following D-076, D-077 and D-079.
- Swapping a container runtime for a native package can strand the old container's state paths → keep the existing `appDir` layout and activation ordering, move the 1.5.x config store aside rather than migrating it (providers and rules are file-owned, D-076), and verify the effective config and route with the pinned build before cutover acceptance.
- The dependency was unpublished when this change was authored → resolved: nix-fleet `main` publishes both outputs at the consumed pin; no local override is committed.
- The tree also carries the applied `telemetry-backends-home-forge` relocation → the standing arrangement is that a deploy carries the staged tree, so the Bifrost gate and the relocation's own gates are both consumed before the cutover; the embedding regression is what this change verifies.
- Removing the compatibility path too early could revive the client failure → remove nothing until the plugin path passes the actual-factory regression.

## Migration Plan

1. Pin a published nix-fleet revision whose `aarch64-linux` outputs expose both `bifrost` and `bifrost-voyage-plugin`; verify the version and artifact paths. Stop if they are absent.
2. Wire the two package outputs into the gateway module and replace the static image source; render the plugin entry into the effective config; add the config-render test.
3. Build the `aarch64-linux` artifacts and prove live plugin load and normalization through a real embedding request on `aarch64`.
4. Review and run focused validation, then parent-owned full gates on the chosen rollout tree.
5. Run the parent-owned gates over the staged tree and deploy the runtime swap and plugin entry together (the tree also carries the applied `telemetry-backends-home-forge` relocation, per the standing arrangement). Verify the recreated gateway, float/base64 SDK calls, existing-index query, and the failed-page retry.
6. Deploy the runtime swap and plugin entry together. Verify the recreated gateway, float/base64 SDK calls, existing-index query, and the failed-page retry.
7. Roll back the runtime and plugin configuration together. No database or index restore is needed; original indexed vectors are untouched. Rollback restores the prior request incompatibility, not successful embeddings.

## Verification References

- Recon report: `/home/saurabhj/.pi/agent/sessions/--home-saurabhj-Projects-dev-nix-homelab--/subagent-artifacts/outputs/7e17c113-5b16-4451-9bc9-335e72b3ab96/docs-mcp-voyage-embedding-compatibility-recon.md`.
- Read-only running-image source copy: `/tmp/local/docs-mcp/dist/main-BDg2etpq.js`.
- nix-fleet mechanism (consumed, not owned here): `pkgs/bifrost/default.nix`, `pkgs/bifrost/plugins/voyage/main.go`, `tests/bifrost/voyage_check.py`, `modules/flake/packages.nix` in the nix-fleet repository.
- Repo anchors: `modules/knowledge/docs-mcp.nix:93–111`, `modules/ai/bifrost/service.nix`, `tests/check-bifrost-gateway-contract.sh`, `policy/bifrost-config.json` (the image pin in `policy/oci-images.nix` was deleted with the container, D-078).
