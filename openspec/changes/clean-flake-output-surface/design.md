# Design — clean flake output surface

## Context

Measured surface before the change (`nix eval` against the tree, not recollection):

| Output | Content | Origin |
| --- | --- | --- |
| `nixosConfigurations` | 3 hosts | `modules/flake/host-registry.nix` |
| `modules.nixos` | 60 aspects | every discovered contributor |
| `packages.<system>` | 29 names, six roles | `modules/flake/packages.nix` + nix-fleet |
| `checks.<system>` | 10 | treefmt, scaffold contract, deploy checks, nix-fleet |
| `devShells`, `formatter` | 1 each | `modules/flake/dev.nix` |
| `apps.<system>` | `update`, `update-packages` | `modules/flake/package-updates.nix` |
| `deploy` | 3 nodes (deploy-rs schema) | `modules/flake/deploy.nix` |
| `deployHosts` | 3 nodes + `edgeHost` + `deployOrder` | `modules/flake/deploy.nix` |
| `bootstrap` | 1 node | `modules/flake/bootstrap.nix` |
| `nixosModules`, `overlays` | `{}` | flake-parts defaults |
| `legacyPackages.<system>` | `{}` | flake-parts default |

`deployHosts.nodes.<id>` = `{hostName, remoteBuild, sshUser, strictSubstituteOnly,
system}`; `deploy.nodes.<id>` = `{hostname, profiles, sshOpts, sshUser}`. They are
different views of the same `lib/deploy/hosts.nix` records, not duplicates.

## Decisions

### D1: `flake-parts.touchup` allowlist, not deletion of options

`touchup` (`extras/touchup.nix`, shipped by our pin) mirrors the output tree and
publishes only what is enabled. `any.enable = lib.mkDefault false` makes the
surface default-deny and the allowlist the single place that names an output.

*Rejected — leave the empties.* They cost nothing to evaluate, but they make
`nix flake show` claim a module, overlay and package-set contract the repository
does not offer. Three of the thirteen attributes are noise that a reader has to
rule out.

*Rejected — `partitions`.* It exists to split a flake into subflakes so inputs
and `flake.lock` shrink; it does not hide outputs. Not applicable until the
dev-only inputs are worth restructuring.

*Consequence to accept:* a future output that is not allowlisted silently
vanishes from `nix flake show` and from consumers. That is the intended default:
every published name is a decision. The scaffold contract keeps asserting the
allowlist so a rename cannot pass unnoticed.

### D2: one `fleet` output, merged per host

`fleet.hosts.<id>` carries the deploy facts and, where the host has reimage
metadata, its `bootstrap` slice:

```nix
fleet.hosts.<id> = {
  system; hostName; sshUser; remoteBuild; strictSubstituteOnly;
} // lib.optionalAttrs (has reimage facts) {
  bootstrap = { hostName; flake; installDir; … };
};
fleet.edgeHost = "<id>";
fleet.deployOrder = [ "<id>" … ];
```

Why merged rather than side by side: `bootstrap` metadata is already declared
inside the host record (`nixos.hosts.<id>.bootstrap`, materialized through the
host registry). Publishing it under the same per-host key as the deploy facts
makes "everything about this host" one lookup and removes the cross-reference
between two top-level outputs. Hosts that are adoptions (not reimages) carry no
`bootstrap` attribute at all rather than a null slot.

`edgeHost` and `deployOrder` stay fleet-level: the edge is a role assignment and
the order is a property of the sequence, not of any one host.

*Rejected — `fleet.{hosts,bootstrap}` side by side.* Smaller data move, but keeps
two shapes to learn and keeps "which output holds host X's reimage facts" a
question.

*Rejected — folding the fleet view into `deploy`.* deploy-rs owns that
attribute's schema; `deployChecks` and `deploy-rs` itself read it, and a foreign
key there is a compatibility risk for no gain.

*Rejected — keeping `deployHosts`/`bootstrap` and only hiding the empties.*
Cheapest, but leaves the two headline names unexplained, which is what the
investigation identified as the actual clutter.

### D3: only `fixture` is hidden from the inherited package list

Each inherited entry was checked against nix-fleet before deciding:

| Entry | Read by | Verdict |
| --- | --- | --- |
| `ci` | nix-fleet workflows (`packages.$RUNNER_SYSTEM.ci`) | keep |
| `ci-tailscale` | `pin-cache.yml:123` reads `$FLEET#packages.$RUNNER_SYSTEM.ci-tailscale` | keep |
| `cache-root` | `promote.yml`, `verify-cache.yml` (pin subject); `checks.packages` | keep |
| `cache-api-url`, `cache-substituter-url` | workflows | keep |
| `cache-public-key`, `ci-coordinator-ci`, `arm-expensive` | documented in nix-fleet `docs/contracts/{ci,builders}.md` | keep |
| `ci-coordinator-fixture`, `ci-coordinator-arm-expensive` | zero references anywhere | keep (unknown external automation; revisit upstream) |
| `fixture` | nix-fleet's own tests only; nothing reads it through this flake | hide |

Hiding is a one-line `touchup.attr.packages.any.attr.fixture.enable = false`, so
reverting is cheap if a consumer appears.

The larger `packages` problem — six roles under one name — is **not** solved
here. `packages` is typed `lazyAttrsOf types.package`, so nesting is impossible;
moving roles (host profiles are already `checks`, `write-*` are apps) touches
deploy and CI paths and deserves its own change. This change leaves the roles
intact and records them in `docs/research/flake-output-shape.md`.

## Risks

- **A hidden output breaks CI at dispatch, not at PR time.** Mitigated by the
  per-entry audit above and by keeping every name a workflow reads. `cache-root`
  and `ci-tailscale` are the two most load-bearing; both stay.
- **Renamed paths break silently in shell scripts.** `scripts/resolve-host-config.sh`
  fails closed by construction (it errors when the attribute is missing), and the
  scaffold contract asserts the exact `fleet` shape, so a missed consumer fails a
  check rather than a deployment.
- **`touchup` changes what `nix flake check` evaluates.** `nix flake check
  --no-build` must be run after the change to confirm nothing it used to evaluate
  has become unreachable.

## Verification

1. `nix eval` against the new surface: the allowlist is exactly the published set,
   `fleet.hosts.<id>` carries the merged fields, `bootstrap` is absent on adoption
   hosts, and the three empty outputs are gone.
2. `nix flake show` lists only the allowlist (no `nixosModules`, `overlays`,
   `legacyPackages`).
3. `nix flake check --no-build` evaluates.
4. Contract tests: scaffold, web-catalog, geopulse (reads `.#` paths), deploy.
5. `just checks all` as the parent-session gate.

## Rollback

Revert the output-surface contributor and the two publishing modules; `deployHosts`
and `bootstrap` return with their previous contents, and no host configuration is
touched either way.
