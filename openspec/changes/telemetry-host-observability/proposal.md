# Proposal

## Why

Every host already ships node, journal and scrape-health telemetry, but three things that make a host series attributable and self-describing were missing, and one that makes a log line joinable to a trace was off:

- The node exporter ran without the systemd collector, so no unit-state series existed — a crashed or flapping unit was visible only in the journal, not in the metrics store.
- Nothing scraped the Tailscale daemon's own Prometheus endpoint, so tailnet health was invisible from the fleet's own metrics plane.
- No telemetry carried an identity that joins to the canonical host record: a series or a journal record could name the scrape target, not the host the fleet's inventory, deploy metadata and web policy all reference.
- Journald shipping left `trace_id`/`span_id` values as they arrived, so a journal record could not be correlated with the trace it belongs to.

All four are nix-fleet contract surfaces (published at `a48a1dcf`), and two of them are producers we inherit by selecting aspects this fleet already selects. Nothing needs local wiring, which is exactly why the adoption is worth pinning rather than writing: there is no code to review, only effective values to hold.

**Core Value:** Host telemetry is attributable to a canonical host ID and unit state and tailnet health reach the fleet's metrics plane, on the same contract nix-fleet publishes, with no local restatement.

**Constraints:**

- The collector contribution must stay additive. Upstream first published it with `mkDefault`, where a consumer's own `enabledCollectors` list *replaced* it instead of extending it; the fix is an `mkAfter [ "systemd" ]` contribution, and this change depends on the published fix rather than working around it.
- `identity.environment` stays null. This fleet has no environment concept, and inventing one to fill an upstream label would be a second naming authority beside the canonical host IDs.
- Nothing is gated, authenticated or admitted by these producers. They are additive telemetry sources; the only routing separation in this area remains D-083/D-084.
- No consumer privilege grant is acceptable for either producer: a host-level observability feature that needs a newly widened Nix privilege is a design fault, not an adoption.

## What Changes

- The nix-fleet input moves to `a48a1dcf` (flake pin and the CI caller reference), which carries the host-observability contract. No other lock node moves.
- `services.telemetry.scrape.tailscale` (`100.100.100.100:80`) becomes a real scrape job on every host that selects `telemetry-metrics`; the registration is nix-fleet's, the realization follows from a selection this fleet already makes.
- systemd unit-state collection arrives through the existing `node-exporter` aspect: `enabledCollectors = [ "systemd" ]` on the ordinary `node-exporter` account, with the `AF_UNIX` allowance the public system DBus API needs.
- `services.telemetry.identity.hostName` resolves to the canonical host IDs, so OTLP `host.name`, the scrape `host` label and journal `host_name` join back to `oci-melb-1`, `la-admin-1` and `home-forge`; `identity.environment` remains null.
- `services.telemetry.journald.normalizeTraceContext` defaults on: exact root or JSON-message `trace_id`/`span_id` values (32/16 lowercase hex, trace-only allowed, source keys winning even when malformed) are normalized and messages and metadata are preserved before the disk buffer. The opt-out stays `= false` and we do not take it.
- The scaffold contract gains an effective-value section (`7n-4`) with a throwaway-copy mutation: the configured collector list, the rendered unit's systemd flag and `AF_UNIX` family, the realized scrape job and its canonical host label, the identity join and the journal default are pinned, and a host that states its own collector list must still receive the contributed collector.
- `ARCHITECTURE.md`, `STRUCTURE.md` and `docs/decisions.md` (D-085) record the contract, the defect class and the verification rules; `docs/architecture.md` carries no host-observability content and is left alone.

## Capabilities

### New Capabilities

- `host-observability`: host-level telemetry producers, their identity contract, and how an adopted upstream contract is pinned by effective value rather than by flag.

### Modified Capabilities

(none)

## Impact

- `flake.lock` (nix-fleet pin), `.github/workflows/ci.yml` (caller reference alignment).
- `tests/check-dendritic-scaffold-contract.sh` (section 7n-4: effective-value pins plus the collector-composition mutation).
- `ARCHITECTURE.md`, `STRUCTURE.md`, `docs/decisions.md`.
- Host records: unchanged. Every host already selects the aspects that realize the new producers, and no host gains or loses a selection.
- Live state: new metric series (systemd unit state, Tailscale) and new label values on existing series; no historical rewrite and no queue or WAL identity change, so the producer endpoints stay valid across the deploy.
