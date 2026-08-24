## 1. Paperless v3 Compatibility

- [x] 1.1 Bind `paperless-group-seed.service` to `services.paperless.environmentFile` in `modules/services/paperless/default.nix`.
- [x] 1.2 Set `PAPERLESS_CONSUMER_DELETE_DUPLICATES=true` in `modules/services/paperless/default.nix` to retain the v2 ingestion policy.

## 2. Validation

- [x] 2.1 Evaluate `oci-melb-1` and confirm `paperless-group-seed.service` receives the configured environment file and duplicate rejection is enabled.
- [ ] 2.2 Run `openspec validate fix-paperless-group-seed-environment --strict` and the relevant flake validation.
