# Design

## Context

nix-fleet owns the telemetry contract, the collector and the exporter mechanism; this repository owns policy and placement. The host-observability surface is therefore unusual for this repo: adoption adds no local module, no option and no host-record change. Every effect arrives through an aspect this fleet already selects (`node-exporter`, `tailscale`, `telemetry-metrics`, `telemetry-logs`), which means the whole change is a pin move plus the assertion that the resulting effective values are the intended ones.

That shape is what the defect below made concrete. A verdict on an adopted contract cannot rest on the contract's own gate, because the gate that missed the defect ran in exactly this position.

## Decisions

### 1. Adopt the published contract as-is; selection is the adoption

No local `enabledCollectors`, no local scrape registration, no local identity option, no journal override. The fleet states nothing that nix-fleet already states, and the only local edit is the pin and its caller reference.

Rejected: binding the systemd collector locally to be safe. A local copy of a contribution that upstream fixes is a second authority that silently wins, which is the failure mode this repo has repeatedly removed (D-066, D-068).

### 2. Verify by effective value, including the composition case

The pins read the configured collector set, the rendered exporter unit (`--collector.systemd` and the `AF_UNIX` family), the realized scrape job with its canonical `host` label, `identity.hostName`, `identity.environment` and the journal default. They also run one mutation on a throwaway copy: a host that declares its own `enabledCollectors` list must still receive the contributed collector.

Why this rather than a cheaper check: the intermediate revision (`aa162629`) defined the collector contribution with `mkDefault`, so a consumer's explicit list replaced it instead of extending it. Upstream's own tests passed on that revision — the composition case was simply absent — so a test borrowed from upstream, or a check for "does the contract declare a systemd collector", would have certified the defective revision. The mutation is the part that fails on the defect class.

Rejected: pinning the contribution form in nix-fleet source (not ours to read), and pinning only the collector list without the rendered unit (a list can be right while the unit loses the flag or the address-family allowance the collector needs).

### 3. The identity join is the canonical host ID; the environment label stays null

OTLP `host.name`, the scrape `host` label and journal `host_name` all resolve to the IDs the fleet inventory, deploy metadata and web policy reference. `identity.environment` stays unset: this fleet has no environment dimension, and inventing a value to fill an upstream label would create a second naming authority beside the canonical IDs.

Consequence to accept knowingly: new label values mean new metric series. There is no historical rewrite, and no queue or WAL identity change, so producers keep their endpoints and their buffered state across the deploy.

### 4. No consumer privilege grant

Neither producer needs one, and neither is granted one. The exporter collector uses the public system DBus API through the `AF_UNIX` allowance on its ordinary static account, and the Tailscale endpoint is served by the daemon-owned local API proxy before the browser session gate, so it is UID-independent. Both were verified rather than assumed: the exporter runs as `node-exporter` with `DynamicUser = false`, and the scraper runs as `vmagent` with no supplementary groups.

Rejected: widening the account or the service sandbox to make the scrape work. A host-observability adoption that needs a new privilege is a fault in the feature, not a cost of adopting it.

### 5. Verify outcomes, not flags

The systemd leg is verified by collector success and the presence of unit-state series; the Tailscale leg by a daemon-specific series. A flag check (`--collector.systemd` present) or an HTTP status check (the endpoint answers) would each pass while the feature was inert — with web-client fallback disabled, a failed lookup can still answer a successful status with a page body instead of metrics.

### 6. Accept the journal correlation default

The default is narrow — exact root or JSON-message identifiers, 32/16 lowercase hex, trace-only allowed, source keys winning even when malformed — and preserves messages and metadata before the disk buffer. We take the default and keep the documented opt-out unused; overriding it locally would be a restatement of a contract default with no fleet-specific reason.

## Risks

- **Series churn.** New labels and new producers add series. Retention and the store's capacity absorb this; the alternative (rewriting history) does not exist.
- **Upstream drift.** The observed values could move again. That is acceptable: the pins are the mechanism that makes such a move visible on the next pin bump rather than at deploy time, and a pin that fires is meant to be re-derived against the published contract, not silenced.
- **Coupling to an upstream label contract.** Cross-repository verification reads nix-fleet's realized scrape configuration. It is consumer-side evidence about values this repository selects, not a dependency on upstream internals.

## Open Questions

None. The one deliberate deviation from a filled-in contract (a null environment label) is recorded as a decision, not left open.
