## 1. Preconditions and baseline

- [ ] 1.1 Confirm Stage 8 canonical host identity is complete; capture evaluated ntfy users, ACLs, daemon routing, publisher token registrations, plaintext template keys, and secret-scope expectations without decrypting secrets.

## 2. Publisher policy

- [ ] 2.1 Add canonical notification publisher policy keyed by known host IDs with typed roles; verify unknown and duplicate publishers fail.
- [ ] 2.2 Derive push-server/ntfy ACL subjects from publisher policy and remove LA's literal list; verify evaluated ACLs are identical.
- [ ] 2.3 Add pure consistency checks covering policy publishers, runtime token contracts, committed plaintext template placeholders, and explicit scope fixtures; verify missing/extra publisher mutations fail by name.

## 3. Extraction boundary and validation

- [ ] 3.1 Remove active fleet identities and routing assumptions from generic daemon/CLI/hook code while preserving typed policy inputs; verify package and runtime configs are equivalent.
- [ ] 3.2 Update notification architecture and future `nix-fleet` extraction guidance; verify homelab policy and SOPS ownership remain explicitly local.
- [ ] 3.3 Run `treefmt --fail-on-change`, `just checks all`, all host evaluations, and `openspec validate normalize-notification-policy --strict`; obtain an independent security review and leave ciphertext plus `.sops.yaml` unchanged.
