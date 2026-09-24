# Tasks

## 1. Adopt the pin

- [x] 1.1 Move the nix-fleet input to the published host-observability revision (`a48a1dcf`, the append-only fix on the withdrawn `aa162629`) and confirm at node level that the lock move touches nix-fleet alone.
- [x] 1.2 Align the CI caller reference to the same revision. The reusable workflow file is byte-identical between the two pins, so this is pin alignment, not a behaviour change.

## 2. Pin the effective values

- [x] 2.1 Add the effective-value section (`7n-4`) to the scaffold contract: enabled and disabled collector sets, the rendered exporter unit's systemd invocation and `AF_UNIX` allowance, its static account, the registered Tailscale scrape source and its realized job with the canonical `host` label, `identity.hostName` against the canonical host ID, the null environment, the unset journal host label and the journal correlation default.
- [x] 2.2 Add the composition mutation: on a throwaway copy, a host declaring its own `enabledCollectors` list must still receive the contributed collector and keep the systemd invocation.
- [x] 2.3 Confirm the new section passes standalone and again inside the full contract battery, then run `just checks all` and the formatter. Both passes are green: section `7n-4` standalone, then the battery over the staged pin — scaffold contract PASS, `just checks all` green (including the view-composition check with only the two upstream-scoped deviations), `treefmt --fail-on-change` clean, and both changes valid strict.

## 3. Records

- [x] 3.1 Change record (`proposal.md`, `design.md`, `tasks.md`, `specs/host-observability/spec.md`).
- [x] 3.2 `docs/decisions.md` D-085: the adoption, the `mkDefault` defect and its forward-only fix, the effective-value pinning rule and the outcome-based verification rules.
- [x] 3.3 Update `ARCHITECTURE.md` and `STRUCTURE.md` where they would otherwise be wrong or silent about the producers, the identity seam and the pin. `docs/architecture.md` carries no host-observability content, so it is not touched.

## 4. Deploy

- [x] 4.1 Deploy `home-forge`, `la-admin-1` and `oci-melb-1` on the new pin, in that order, and confirm no failed units, with the collector restart and the exporter restart recorded. Deployed in that order in one pass (`home-forge` 126 → 127, `la-admin-1` 64 → 65, `oci-melb-1` 326 → 327); each activation succeeded with magic rollback confirmed. Every host restarted `prometheus-node-exporter`, `vector` and `vmagent` — the units this adoption touches — and `home-forge` additionally restarted `opentelemetry-collector`. No failed units on any host.
- [x] 4.2 Confirm the hosts' evaluated toplevels are functionally identical to what they run apart from this adoption (no unrelated package or unit movement rode the pin), using the generation comparison rather than a bare output-path comparison. `nix store diff-closures` between each host's previous and new generation reports only the notify policy file's renamed render (the previously verified content-equivalent change), the provenance copy's size, and the telemetry units; `etc/systemd/system` differs only for `prometheus-node-exporter`, `vmagent` and `vector` (plus `opentelemetry-collector` on `home-forge` and, on `oci-melb-1`, `caddy.service.d/overrides.conf`, whose single difference is its `X-Reload-Triggers` store path). No package or unit moved for any other reason.

## 5. Verify live

- [x] 5.5 Record the verification evidence in this task list and in D-085. The verification ran as a throwaway script (polling store queries plus a journal probe) rather than a repository check, because it exercises running hosts and a live store; its deploy-time and live evidence is recorded in D-085.
