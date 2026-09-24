# Design

## Context

nix-fleet published a named-route contract (main `fb5ac7e3`): `services.telemetry.routes.<route>` declares its own `signals`, route-local `pipelines.<signal>` destination names, and its own `ingress` listener. Route pipelines inherit nothing from the general route, and each route-and-destination pair gets its own receiver, exporter instance, queue and WAL directory. The general route's generated component names are unchanged, so hosts that declare no route behave exactly as before.

Upstream evidence at that revision: `nix flake check` and `nix flake check --no-build --all-systems` both pass, `checks.<system>.telemetry-ingress` evaluates to the byte-identical derivation it produced before the change, and the runtime route harness shows the general route still delivering normally while an AI route exists.

## Goals / Non-Goals

**Goals**

- AI-session telemetry reaches Langfuse and Latitude only when a producer selects the AI route.
- General telemetry keeps reaching the fleet trace store, unchanged in component names, endpoint and queue state.
- Each backend's destination-scoped exporter policy (credential, headers, transport setting) applies to route exporters without being restated.

**Non-Goals**

- Authenticated admission. Upstream states plainly that a route listener has no authentication, enrolment or credential; that is a separate unimplemented change. This change must not be described as protecting the lane.
- Span-level filtering. Enrolled sessions keep every span on every destination; the isolation is between producers, not between span kinds. What a destination receives of a span's *payload* is a separate axis, decided by the output views below: the operational store's copy of a span carries no content carriers, and no span is dropped from any leg.
- Authoring a composition guard. The views are checked with nix-fleet's published composition guard, reused as data rather than re-derived here.
- Producer rebinding in other repositories (Pi's workstation relay) and the canonical inventory record, both requested rather than performed here.

## Decisions

**General route narrowed explicitly rather than left derived.** The general trace pipeline currently derives its destinations from destination presence, which is what put Langfuse and Latitude in the path of every trace. It becomes an explicit one-entry list, so the AI backends are reachable only from the AI route and the intent is readable rather than implied by destination existence.

**The AI route is declared on the gateway host, not in the shared telemetry policy.** A route requires an explicit listener, and the bind address is a host fact — the same reason the general ingress carries its host in the host's private composition. Declaring the route in the shared contributor would give every telemetry host a route without a listener and fail the contract's own validation.

**Destinations are named on the route, including the trace store.** The AI route lists VictoriaTraces alongside the two backends, because route pipelines inherit nothing: an AI session that reached only the backends would be absent from the general store, which is a worse outcome than duplication.

**Endpoint resolution stays canonical.** Producers resolve the AI ingress through nix-fleet's service inventory (`otel-collector.endpoints.ai-otlp.tailnet`) rather than a literal host and port. The gateway binds `100.126.123.74:4319` — the port selected beside the existing general OTLP listener on 4318 — and the matching inventory record is requested upstream so dotfiles can resolve it through `lib.serviceEndpoints.url`.

**Latitude's transport settings carry over unchanged.** Destination-scoped exporter settings are merged per destination instance, so the project header and `compression = "none"` already configured for Latitude apply to `otlphttp/route-ai-latitude` as well. No route-specific restatement is needed.

**The AI route carries three output views, and the operational store's is lean.** A route is one input audience; the views decide what each destination receives of it. Langfuse keeps the generated rich pipeline, since it parses a session, with its vendor keys mapped from the canonical carriers (D-088); VictoriaTraces is the fleet's long-retention operational store, so its leg strips the content carriers the analysis backends parse (`gen_ai.input.messages`/`output.messages`/`system_instructions`, tool arguments and results, the legacy `gen_ai.prompt`/`completion` pair, the generic `input.value`/`output.value`) together with the content-bearing span events, while keeping status, error attributes and timing. Both stores therefore hold the span; only the analysis backends hold the payload. The deny list is honest about its own coverage: a producer whose carriers are not listed reaches the store intact until it is added, so Hindsight's carriers are a binding task rather than an assumed one.

**The composition lives in the fleet telemetry contributor, gated on the route.** A route requires a host-declared listener, which is why the declaration stays in the host's private composition; what a destination receives is fleet policy, so the views, their branch processors and the expected composition are declared in `modules/flake/telemetry.nix` and activated by the presence of the `ai` route. A gateway host that declares the route gets them; a host that selects the OTLP lane without it gets none. The composition partitions the route's declared members, so an assertion fails by name if the route's trace membership changes without the views changing with it.

**The expected views are published as data and checked by nix-fleet's guard.** A native pipeline override means the declaration proves nothing, so the module publishes the expected composition (`fleet.telemetry.outputViews`, read-only and internal) and the contract test runs nix-fleet's `compositionFailures` over the *effective* settings, plus a non-vacuity mutant and direct assertions on the emitted OTTL. Two of the guard's checks are over-broad for this host and are reported upstream rather than worked around: destination uniqueness keys on backend name globally, so a route sharing the store with the general route reads as a double assignment, and the coverage check counts metrics instances the trace views cannot own. Neither motivates aliasing a destination or duplicating exporter policy — the instances, queues and WALs are already separate, and upstream confirmed the checks need scoping.

**Latitude's carrier bridge is version-scoped and never mixes families.** The deployed Latitude reads span attributes only and renders messages from the deprecated `gen_ai.prompt`/`gen_ai.completion` pair, so the view lifts the canonical carriers from the inference event onto the span — but only when the span carries no canonical message carrier at all, and only when the producer set no legacy carrier itself. `gen_ai.system_instructions` is the same canonical key in both representations, so supplying it when a span lacks it mixes nothing. The bridge assumes one inference event per span; a span carrying two would overwrite the same carrier.

## Risks / Trade-offs

- **A destination's payload is a policy decision, and it is now three of them.** The store leg's lean view means a prompt or completion is no longer recoverable from VictoriaTraces once the collector has forwarded it — by design, but it changes what an operator can debug from the trace store alone. Recovery means querying Langfuse or Latitude, whose retention is their own.
- **Gateway-executed destinations sit behind a listener with no admission.** Anyone able to reach the tailnet listener can inject traces that reach both backends. Accepted: it is no weaker than the current general ingress, which today reaches the same backends; admission remains a pending upstream change.
- **The fleet AI gateway is briefly unenrolled.** Until the canonical endpoint record exists, Bifrost cannot select the AI route without a literal address, so its LLM-gateway spans reach the trace store only. Accepted as a short, tracked gap rather than a policy violation.
- **Two lanes must stay distinguishable in documentation.** Recording the lane as routing-only, in the module comment and the decision record, keeps a later reader from assuming the isolation is an access boundary.

## Migration

Purely additive at the collector: declaring `routes.ai` adds a listener and route-scoped exporters, and the general route keeps running as-is. Rollback is deleting the route declaration in the same edit — its listener and exporters disappear with it, and the general route is unaffected. Producer rebinding is a separate edit in the producing repository.
