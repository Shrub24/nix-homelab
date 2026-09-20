## Context

LA's ntfy server currently owns a literal ACL list for all publisher hosts. Publisher identities are fleet policy, while daemon/CLI/hook mechanics are generic and routing plus secret readership remain homelab-specific. Canonical host identity will be supplied by Stage 8.

## Goals / Non-Goals

**Goals:**
- NPOL-1: one typed owner for publisher identities and roles;
- NPOL-2: derive ntfy ACLs from that policy;
- NPOL-3: validate policy, plaintext templates, and runtime secret contracts without touching ciphertext;
- NPOL-4: keep the generic notification component extractable.

**Non-Goals:**
- extracting code to `nix-fleet` in this change;
- generating encrypted secrets or `.sops.yaml` rules;
- changing topics, recipients, tokens, or delivery routing.

## Decisions

### NPOL-1 — Publisher policy references canonical host IDs

A homelab notification-policy contributor declares publisher host IDs and authorization roles. IDs must resolve through the Stage 8 host registry. The ntfy server's placement host does not own the fleet list.

### NPOL-2 — Push-server renders authorization

The push-server/ntfy module transforms publisher policy into ACL subjects and validates the corresponding runtime secret references. The transformation is pure and reused by contract tests.

### NPOL-3 — Security artifacts remain explicit

Committed secret templates are checked against publisher policy, but are not generated if generation would obscure review. `.sops.yaml` reader sets and encrypted files remain operator-controlled. Mismatches fail with the missing publisher named.

### NPOL-4 — Preserve extraction boundary

Package/daemon/CLI/systemd-hook code receives policy through typed options. Homelab host IDs, Telegram topics, ntfy publisher membership, and SOPS paths remain outside the generic implementation.

## Risks / Trade-offs

- **Policy and ciphertext can diverge** → validate template/runtime key contracts and require the operator's normal SOPS workflow for value changes.
- **Canonical identity dependency** → apply only after Stage 8; do not create a temporary duplicate identity table.
- **Extraction pressure causes premature API generalization** → preserve only interfaces already used by the three hosts.

## Migration Plan

1. Capture evaluated ACLs, users, topics, and secret registrations.
2. Add publisher policy and derive identical ACLs.
3. Remove LA's literal list and add negative mismatch tests.
4. Deploy LA and verify publish from each active host.

Rollback restores the literal ACL list; token values and files are unchanged.
