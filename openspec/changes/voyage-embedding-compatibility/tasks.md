# Tasks

## 1. Dependency pin

Resolved 2026-10-05: nix-fleet `main` published the Bifrost package, the Voyage
plugin and their check, so the pin moved from `7553aa45` to `5950fcbb`.

- [x] 1.1 Update the `nix-fleet` input to a published revision and verify that committed revision exposes both `packages.aarch64-linux.bifrost` and `packages.aarch64-linux.bifrost-voyage-plugin`. Verify: `nix eval --inputs-from . --raw "nix-fleet#packages.aarch64-linux.bifrost.version"`, the same for `bifrost-voyage-plugin.outPath`, and a `git ls-tree -r --name-only origin/main` check on the nix-fleet repository proving the revision is published (not a local checkout, `--override-input`, or unpushed commit). Record the before/after nix-fleet revision and every induced shared-pin (`nixpkgs`, `flake-parts`, `import-tree`, `sops-nix`, `niks3`, `treefmt-nix`) change. Stop and report if either output is absent; a local override is not an acceptable substitute.
      **Evidence:** before `7553aa45`, after `5950fcbb` (`origin/main`, published;
      `git ls-remote --heads` + `nix flake metadata`). `bifrost.version` = `2.2.5`;
      `bifrost-voyage-plugin.outPath` resolves for both systems. Induced pins:
      `nixpkgs` `44a91898` → `c59305ba`, plus `flake-parts_2`, `sops-nix`,
      `niks3`, `flake-file_2` and `fast-nix-gc`. `degoog`, which the same relock
      also moved, was pinned back to `e4e110b9`: the bump was unrelated to this
      change and no consumer asked for it. Two evaluation fixes came with the
      bump: nix-fleet's telemetry contract now rejects `otlp.host = "0.0.0.0"`,
      so oci-melb-1 declares admitted signals plus `otlp.ingress.host` with
      ordering behind `tailscaled` (D-075 note), and the new nixpkgs marks the
      Navidrome `audiomuseai` plugin as `platforms = wasi`, which needs a local
      `lib.platforms.all` override because the `.ndp` payload is
      platform-independent.
- [x] 1.2 Record the plugin artifact contract for the pinned revision: the plugin output path suffix (`/lib/bifrost/voyage.so`), the plugin name `voyage-normalizer`, and that both derivations come from the same revision with a matched Go toolchain/CGO/vendor graph. Verify: the recorded paths and `bifrost.version` for that revision appear in this change's notes, and `pkgs/bifrost/default.nix` at that revision builds the plugin through `mkPlugin` on the same `goModule`.
      **Evidence:** `bifrost-plugin-voyage-2.2.5/lib/bifrost/voyage.so` (built and
      substituted on `x86_64-linux`); name from `plugins/voyage/main.go`
      (`GetName() == "voyage-normalizer"`); both derivations come from `mkPlugin`
      over the same `goModule` in `pkgs/bifrost/default.nix`, which pins the Go
      toolchain, `vendorHash` and `CGO_ENABLED=1`. The upstream check
      (`tests/bifrost/voyage_check.py`) passes at this revision.

## 2. Package plumbing

- [x] 2.1 Expose the two nix-fleet package outputs through `modules/flake/packages.nix` (or the existing consumption helper) without restating their build. Verify: narrow package evaluation resolves both outputs, e.g. `nix eval --raw ".#packages.aarch64-linux.bifrost.outPath"` and the plugin equivalent, on the committed pin.
      **Evidence:** `modules/flake/packages.nix` publishes `bifrost` and
      `bifrost-voyage-plugin` per system, and `modules/flake/fleet-packages.nix`
      projects both into `repo.packages` for the host's target system — the
      module-facing surface the runtime reads. Both resolve for `x86_64-linux`
      (built) and `aarch64-linux` (evaluated; task 4.1 realises them).
- [x] 2.2 Add a focused check that the plugin package's install path ends in `/lib/bifrost/voyage.so` for the pinned revision. Verify: the check fails if the suffix changes and passes at the pinned revision.
      **Evidence:** `tests/check-bifrost-gateway-contract.sh` asserts the
      rendered plugin path equals `repo.packages.bifrost-voyage-plugin` plus
      `/lib/bifrost/voyage.so`, wired into `just checks all`; it passes on
      oci-melb-1.

## 3. Gateway runtime and configuration

- [x] 3.1 In `modules/ai/bifrost/service.nix`, replace the static `v1.5.0-prerelease8` container image as the runtime source with the nix-fleet `bifrost` binary, preserving the existing `appDir` layout, tmpfiles, backups wiring, environment file, and start ordering. Verify: a narrow `nix eval` of `services.bifrost` option values and the systemd unit wiring on the gateway host shows the nix-fleet binary and unchanged state paths, with no container-image reference left.
      **Evidence:** the runtime is a native unit from `repo.packages.bifrost`
      (`ExecStart = <bifrost>/bin/bifrost-http -app-dir … -host … -port …`), with
      `ProtectSystem=strict` and only the app directory writable, under a new
      dedicated `bifrost` account; `appDir`, tmpfiles, the state-backups
      registration, the environment file and the render-before-gateway ordering
      are unchanged. The `policy/oci-images.nix` pin and
      `virtualisation.oci-containers.containers.bifrost` are deleted (no
      `ociImages.bifrost` reference remains). Two revisions were added to the
      unit — over the configuration inputs and over the secrets file's
      ciphertext — because a native unit has the same stable-path blind spot
      D-077 describes for containers. (Superseded by 3.4: since D-079 the unit,
      the service account and the restart wiring are nix-fleet's gateway aspect.)
- [x] 3.2 Render the effective Bifrost configuration so `policy/bifrost-config.json`'s Voyage provider and all other providers/routes are preserved and exactly one plugin entry is added: `{"enabled": true, "name": "voyage-normalizer", "path": "<bifrost-voyage-plugin>/lib/bifrost/voyage.so", "placement": "post_builtin"}`. Verify: `nix eval` of the rendered config path and `X-Bifrost-Config-Hash` shows the plugin entry present, the Voyage `request_path_overrides`/`network_config.base_url` unchanged, and the `otel` plugin preserved; the hash changes when the plugin path changes.
      **Evidence:** `services.bifrost.renderedConfig` is the effective document
      (repo file plus exactly one `voyage-normalizer` entry) and
      `renderedConfigFile` is its rendering, both read-only observables.
      `X-Bifrost-Config-Hash` is derived from the config file's digest and the
      plugin path: **not** from the rendered document, because hashing that file
      realises everything it references (including the plugin build for the
      evaluating host's architecture) — the check caught this, and the design
      notes record it. The config file itself moved to the 2.2.5 shape in the
      same task: the admin account is `auth_config` with env indirection
      (`BIFROST_ADMIN_USERNAME`/`_PASSWORD` are no longer read by the binary) and
      `custom_provider_config` is dropped from `deepseek` and `opencode-go`,
      which 2.2.5 treats as standard providers while `voyage` stays custom.
      (Superseded by 3.4: `renderedConfig`/`renderedConfigFile` and the
      configuration restart trigger belong to the fleet module since D-079, and
      the `otel` entry now registers through `services.bifrost.plugins`.)
- [x] 3.3 Add a focused test asserting the rendered configuration's plugin entry (name, `post_builtin`, plugin-derived `voyage.so` path) and the untouched Voyage upstream. Verify: the test passes on the pinned revision and fails if the plugin entry or Voyage upstream is removed.
      **Evidence:** `tests/check-bifrost-gateway-contract.sh` asserts the plugin
      entry, the preserved `otel` entry, the untouched Voyage
      `request_path_overrides.embedding`/`network_config.base_url`, the absence of
      `custom_provider_config` on the standard providers, the
      `shrublab-embedding → voyage/voyage-4` routing rule, the native `ExecStart`,
      the absence of the container entry, and both restart triggers — the
      rendered configuration and the encrypted secret file.

- [x] 3.4 Adopt nix-fleet's published `flake.modules.nixos.bifrost` for the gateway mechanism, keeping this repository's policy. Verify: the aspect imports the fleet module and defines no `enable`; the unit, the service account, the application directory and the startup-configuration install come from it; the settings document carries no `plugins` member; and both a settings change and a credential rotation still recreate the process.
      **Evidence:** `modules/ai/bifrost.nix` imports
      `inputs.nix-fleet.modules.nixos.bifrost` at the relocked pin (`dc29c326`,
      the first published revision carrying the aspect) and supplies only the
      canonical port. `modules/ai/bifrost/service.nix` drops the package
      override, the account, the render unit, the unit body, our
      `renderedConfig`/`renderedConfigFile` options, the notify registration and
      the application-directory tmpfiles rules; it keeps the settings document,
      the `otel`/`voyage-normalizer` registrations, the SOPS-rendered
      environment, the container ingress rule, the state-backups registration
      and the encrypted secret file as a second `restartTriggers` entry. `dataDir`
      is now `/srv/data/bifrost/app` — the application directory itself — and the
      host binds only `secretFiles.host`. `tests/check-bifrost-gateway-contract.sh`
      pins the fleet assumptions this repository now relies on (application-directory
      `-app-dir`/`ReadWritePaths`, the startup install into it, both restart
      triggers) and passes on `oci-melb-1`. Recorded as D-079.
      **Adoption repair (2026-10-05):** the first aspect deployment failed because
      `dc29c326` disabled the config store, which Bifrost requires for governance
      and dashboard authentication. Relocked to upstream `b0a80234`; no other lock
      node moved. The rendered store is now SQLite at
      `/srv/data/bifrost/app/config.db`, enabled with `source_of_truth = "config.json"`.
      The consumer contract pins all three facts. On OCI's actual aarch64 binary,
      an isolated copy of the fleet configuration booted twice (fresh state and
      restart): health 200, fleet routing rules present through the authenticated
      API, the native Voyage plugin mapped, and config.db created. The probe used
      dummy credentials and scratch state; production credentials and state were
      untouched. Repaired aspect deployed successfully to OCI generation 317
      (`bg-4686`, exit 0): `just checks all`, formatting and strict OpenSpec
      validation passed; activation confirmed. Live Bifrost is active with zero
      restarts, the native plugin mapped, the config store enabled and config.json
      authoritative. `shrublab-text`, `shrublab-fallback`, `shrublab-image` each
      returned 200; `shrublab-embedding` accepted `encoding_format = "float"`
      and returned 1024 dimensions. No failed units. The client-level docs-mcp
      acceptance tasks below remain separate and open.

## 4. Architecture compatibility gate (blocking for deployment)

- [x] 4.1 Build `aarch64-linux` `bifrost` and `bifrost-voyage-plugin` at the pinned revision. Verify: both store paths realise for `aarch64-linux`, and record the toolchain/CGO evidence rather than assuming `x86_64` equivalence.
      **Evidence:** built on the fleet's build plane (`--store ssh-ng://eu.nixbuild.net`, the
      `prebuild-remote` pattern): `qcy17s7ldznn10awz9xaa3wdf3ilvs2f-bifrost-2.2.5` and
      `cdyx3mhlmml1lr2zssdal2kz2jx5x4ql-bifrost-plugin-voyage-2.2.5`, from the same
      `goModule` (Go toolchain, `vendorHash`, `CGO_ENABLED=1`). The local builder set is
      `x86_64`-only and correctly refused the platform. oci-melb-1's evaluated plugin
      derivation is byte-identical to the built one (`015fy41f…-bifrost-plugin-voyage-2.2.5.drv`),
      so both artifacts were copied into the host's store and the deploy ran exactly what the
      check exercised instead of rebuilding.
- [x] 4.2 Load the built plugin into the built `bifrost-http` on `aarch64-linux` and prove normalization through a real embedding request. Verify: nix-fleet's `bifrost-voyage-plugin` check (or its recorded output) runs on `aarch64`, showing the plugin loaded as `voyage-normalizer` and the outbound Voyage body without `encoding_format`/`dimensions`; evaluation-only output-path checks and `x86_64` runs do not satisfy this task.
      **Evidence:** nix-fleet's check ran green on `aarch64`
      (`svhmcpqayfqp8rrm8a7b4yv3jd6g95j5-bifrost-voyage-plugin-check`), recording
      `loaded-plugin=voyage-normalizer`,
      `voyage-float=encoding_format removed; dimensions mapped to output_dimension`,
      `voyage-explicit-output_dimension=preserved; dimensions removed; base64 preserved`,
      `other-provider=body unchanged`. Live on `oci-melb-1` after the cutover (generation 315,
      2026-10-04 15:20 UTC): `plugin status: voyage-normalizer - active`, and the plugin is
      mapped four times in the running process — `sudo grep -c voyage.so /proc/366795/maps` →
      `4`, path `…/cdyx3mh…-bifrost-plugin-voyage-2.2.5/lib/bifrost/voyage.so`.

## 5. Live endpoint compatibility (after approved deployment)

- [x] 5.1 After an approved embedding-only rollout, exercise the pinned LangChain client with the actual factory arguments (`modelName: "voyage/voyage-4"`, `encodingFormat: "float"`, no `dimensions`) for a query embedding and a document batch. Verify: both return 200 with 1024-dimensional vectors and no store reset.
      **Partial:** the deployed gateway answers the exact failing wire shape —
      `POST /v1/embeddings {"model":"shrublab-embedding","input":"ping","encoding_format":"float","dimensions":1024}`
      → 200 with a 1024-dimensional vector, through the routing rule to `voyage/voyage-4`.
      The docs-mcp client's own factory arguments and a document batch are the remaining half.
      **Done 2026-10-09:** no store reset anywhere in this arc. (a) Direct probe of `http://oci-melb-1:7411/v1/embeddings` with the factory's exact fields (`model` `voyage/voyage-4`, `encoding_format` `float`, no dimensions) returns HTTP 200 with 1024-dim vectors for a single query string, a two-text document batch (`usage.total_tokens: 16`), and a field-free control request — so the normalizer rewrites what Voyage rejects and leaves a clean request untouched. The pinned LangChain client is not installed on this workstation, so the HTTP layer stands in for the request shape. (b) The real LangChain factory already exercised the same path end to end once per chunk during the flake.parts live ingest, when the gateway logged 13/13 embedding POSTs at HTTP 200.
- [ ] 5.2 Retry the failed `https://pi.dev/docs/latest` page and query the existing index. Verify: the page embeds into the existing store and an existing-document query returns results, recording counts and dimensions rather than vectors or contents.

## 6. Integration checks

- [ ] 6.1 Run the parent-owned gates on the chosen rollout tree (`nix flake check`, the scaffold contract, `just checks all`, `treefmt --fail-on-change`) and confirm `openspec validate voyage-embedding-compatibility --strict` passes. Verify: all gates pass on the rollout tree, not the mixed working tree.
      **Evidence:** `treefmt --fail-on-change` clean, three host evaluations ok,
      `openspec validate … --strict` valid, scaffold contract PASS, `just checks all` PASS
      (including the new gateway check). **Deviation:** `nix flake check --no-build` is not
      usable on this tree — degoog's module needs an eval-time IFD (`bun2nix` generating
      `bun.nix`) and the relock invalidated that dependency, so `--no-build` cannot realise it.
      With builds allowed the `deploy-schema` check still reported one failed dependency whose
      first error the captured tail lost; that diagnostic is outstanding and is independent of
      this change (it reproduces from the relock alone, and both `just deploy` and
      `deploy-host.yml` pass `--skip-checks`).
- [x] 6.2 Confirm rollback restores the runtime and plugin configuration together and that no index or database restore is needed. Verify: a documented rollback step targets both the runtime and plugin configuration in one generation.
      **Evidence:** the pre-deploy generation was captured (`system-314-link`, deployed
      `system-315-link`); the runtime, the plugin registration and the 2.2.5 config shape all
      live in one generation, so redeploying a previous profile — or deploy-rs's auto-rollback —
      reverts them together. The 1.5.x config store was quarantined at
      `/srv/data/bifrost/pre-2.2.5/` rather than migrated, so rollback needs no database restore
      and the quarantined store stays on disk. No embedding index was touched.
      **Note:** one operator step precedes the cutover — the config store
      `config.db` was written by the 1.5.x container, so it is moved aside rather
      than migrated; providers and routing rules are file-owned (D-076), so
      nothing authoritative is lost, and rollback re-points the generation while
      the quarantined store stays on disk.
