## 1. Paperless v3 Compatibility

- [x] 1.1 Bind `paperless-group-seed.service` to `services.paperless.environmentFile` in `modules/flake/paperless/core.nix` (was `modules/services/paperless/default.nix` when this task ran).
- [x] 1.2 Set `PAPERLESS_CONSUMER_DELETE_DUPLICATES=true` in `modules/flake/paperless/core.nix` (was `modules/services/paperless/default.nix` when this task ran) to retain the v2 ingestion policy.

## 2. Validation

- [x] 2.1 Evaluate `oci-melb-1` and confirm `paperless-group-seed.service` receives the configured environment file and duplicate rejection is enabled.
- [x] 2.2 Run `openspec validate fix-paperless-group-seed-environment --strict` and the relevant flake validation (run 2026-09-21: strict validation valid, `nix flake check --no-build .#` passed on the archived head).
