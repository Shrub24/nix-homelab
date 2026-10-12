## 1. Disable Hindsight background work

- [ ] 1.1 Set `HINDSIGHT_API_WORKER_ENABLED=false` in the Hindsight container environment, leaving API and control-plane enablement unchanged.
- [ ] 1.2 Extend the host placement contract to pin the worker setting on home-forge and its absence on hosts without Hindsight.
- [ ] 1.3 Run focused evaluation and repository checks; deploy home-forge; verify the container is running with the worker disabled while API/control-plane health remains good.

## 2. Wire Hindsight traces

- [ ] 2.1 Confirm the trace-content policy with the operator before enabling export; Hindsight's pinned implementation emits prompt, completion, and system-instruction event attributes.
- [ ] 2.2 Use the pinned fleet telemetry-ingest contract to configure the private collector endpoint, stable Hindsight service identity, and the approved content-handling behavior.
- [ ] 2.3 Validate the rendered environment and collector route, run repository checks, deploy home-forge, and verify a fresh Hindsight trace in every configured destination.

## 3. Clear stale operations

- [ ] 3.1 Record status counts, then transactionally delete only `pending` and `failed` rows from Hindsight's `async_operations` table after the worker-off and trace deployments are confirmed.
- [ ] 3.2 Verify pending/failed counts are zero and completed/cancelled operations plus Hindsight memory data are preserved.
