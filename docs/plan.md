# Plan

Scratchpad for what is in flight and what to try next. Durable rationale belongs in
`docs/decisions.md` (D-nnn); completed work belongs in `docs/context-history.md`. An item leaves
this file when it lands or when a decision replaces it — nothing here is a record.

## In flight

### Deploy the pending generations

The three hosts carry work that is evaluated but not activated. Deploy order is
`la-admin-1` → `oci-melb-1` → `home-forge`, except that nixbot's cache-trust rule reaches
`oci-melb-1` and its service reaches `home-forge`, so those two are ordered against each other.

- `oci-melb-1` — the last two activations rolled back. Both causes are fixed in this tree: the
  `nixbuild` provisioning role was created `NOLOGIN` while peer consumers hold no password, and
  `podman-inbox-zero` never passed its readiness probe because the standalone server binds the
  container hostname rather than loopback. `activationTimeout` is now 900s because a switch on
  this host costs ~200s before the first container starts.
- `home-forge` — nixbot, plus the activation whose `ExecStartPost` retry budget ran out on a
  failed unit and forced a rollback.
- `la-admin-1` — nothing blocks it.

### nixbot acceptance

The service runs; the first real PR build is the acceptance run. What is unproven live, in the
order it fails cheapest, is in `docs/runbooks/nixbot.md`; the two that matter here are that the
`checks` attribute builds on both architectures through the fleet's builders, and that a main
push runs `cache-retain` and moves both rolling pins.

## Open decisions

### Dependency pin posture

Two nixpkgs instances are in play: ours (via nix-fleet) and `authentik-nix`'s own. Making
`authentik-nix` follow ours was measured and rejected — it invalidates nix-community's cache and
costs +200 builds on the host that runs Authentik (D-134). The paperless pin is gone and nixbot
tracks upstream `main` (D-134); `degoog` and `bun2nix` stay release-pinned so Renovate can track
them and a lockfile change shows up as a failing `check-degoog-bun-deps`.

### Gatus probe paths and the Access service token

Every route still declares `health.path = "/"`, which behind a service token is the application's
login page: `200` for Grafana and Homepage, `302` for Paperless. Moving each route to an endpoint
that answers without application authentication, and deciding whether the probe class is the
public URL or the catalog endpoint, precedes turning on strict service-token authentication —
otherwise those routes go red for a reason that is not an outage.

### Identity: enforcement beyond the session gate

The login gate withholds a session; a session that predates an address change still passes into
applications. Closing that needs an application policy (`email_verified_address == email`,
`policy_engine_mode = "all"`), off for the console clients so a broken mailbox stays repairable.
Two smaller items stay deferred with their reasons recorded: a courtesy prompt for an
already-signed-in unverified user (a redirect stage cannot template `next`), and MFA enrolment at
registration (the stage's `configuration_stages` relation makes the configure path a chooser).

### Perimeter authority

Either Access stays the perimeter and its per-route policies collapse to one coarse rule, or
route-level authorization moves to the origin and Access keeps only the host gate. Not blocking;
revisit at the second enrolled person or the first route that genuinely diverges.

### SparkyFitness

The backend runs from a fork pin because upstream strips the issuer's trailing slash and no
Authentik issuer matches — upstream tracks it as
[#2772](https://github.com/CodeWithCJ/SparkyFitness/issues/2772); revert when a release carries the
fix. Separately, its nginx rate-limits by client IP and every request arrives from the proxy:
decide whether to set a real-IP header together with the trusted-hop count once acceptance shows
the limit firing on ordinary traffic.

## Bounded follow-ups

`TD-` identifiers are the ones still live; resolved entries were dropped from this file once their
decision landed.

- `TD-09` — Cockpit resolves its identity from the `"cockpit-admin"` route key, which no longer
  exists; re-enabling it means re-declaring the route rather than relying on the override.
- `TD-10` — monitoring residuals: `ExecStopPost` labelling success after a failure, shallow
  self-monitoring hardening, and the real-service predicate excluding arbitrary units.
- `TD-11` — `tests/check-identity-contract-directionality.sh` is still one file serving several
  contracts; split it with shared fixtures rather than growing it.
- `TD-17` — the support quartet (`provenance`, `oci-images`, `fleet-packages`, `web-policy`) stays
  in `modules/flake/`; move it only on real ownership pressure.
- `TD-24` — the capture-ordering seam is expressed by restic's unit name; a second capture backend
  would need a neutral capture-target contract.
- `TD-25` — one encrypted `oidc.yaml` per host serves every client of that host, so moving a
  workload re-encrypts and re-binds; per-client files would make relocation one re-encrypt.
  Operator-owned, trigger is the next workload move.
- `TD-27` — nix-fleet extraction candidates, strongest first: `networking.nix`, then `base.nix`
  (after its policy values become typed options), `provenance.nix`, `base-host-recovery.nix`.
- `TD-29` — Cockpit and Termix each hand-roll a `tailscale serve` front; both aspects are
  unselected, so converge whichever is selected first.
- Windows VM lifecycle: an idle reaper plus socket-activated RDP, gated on proving a graceful
  `windows-vm-stop` first.
- The blueprint gate calls `Importer.validate()` and then polls the applied hash; collapsing them
  needs an experiment on the VM harness, because the gate must still tell a rejected blueprint
  from a stale one.
- `AGENTS.md` and the jj skill should each state the commit rhythm once — a fix to written lines
  goes back through `absorb`, a new concern through `split` — without restating the mechanics.

## Known ceilings

- `authentik-nix` tracks upstream `main` with no `follows` and no Renovate manager, so a
  `nix flake update` can move it and upstream may reshape blueprint fields that only fail at
  apply time. Accepted; following our nixpkgs is measurably worse (D-134).
- Senders share one domain and one relay, so a blocklist or reputation hit reaches all of them.
  Revisit if one service's volume starts affecting the others (`docs/mail.md`).
