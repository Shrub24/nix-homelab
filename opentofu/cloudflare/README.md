# Cloudflare

Two independently applied roots share the existing R2 backend credentials, not state.

| Root | State key | Owns |
| --- | --- | --- |
| `opentofu/cloudflare/` | Existing `backend.hcl` key | Policy-derived service DNS and per-service Access applications |
| `opentofu/cloudflare/foundation/` | `opentofu/cloudflare/foundation.tfstate` | Shared origin DNS, Access policies/token/IdP, zone settings and rulesets, Resend DNS, R2 buckets/domains, Bot Management |

The operator entrypoint remains `just tofu::apply`. Add `--foundation` for shared
infrastructure and `--sync` to export and validate the current web policy first.
Other arguments pass unchanged to OpenTofu. Apply retains its normal confirmation.

```sh
just tofu::apply --sync
just tofu::apply --foundation
just tofu::init --foundation -reconfigure
```

Initialization is automatic only when a root has no backend metadata. Explicit
`init` accepts native options; backend reconfiguration is not forced on each apply.

Before a service apply, the wrapper reads foundation's `service_access` output
from state into the ignored `foundation.auto.tfvars.json`. This reads policy IDs,
IdP IDs and session duration, not the Cloudflare objects. Foundation must have
been applied before service publication can use it. The service provider has no
foundation resources in its refresh graph.

The existing runtime renderer supplies each root only the variables it consumes.
Encrypted credentials stay in the existing operator-managed SOPS sources. Both
roots commit their provider lock at Cloudflare 5.26.0.

## Storage ownership

Foundation adopts the ten buckets listed in `foundation/config.auto.tfvars`
through declarative imports. Bucket deletion is blocked by `prevent_destroy`;
bucket objects, backup contents and application data are not managed here.

The two public R2 domains are `assets.shrublab.xyz` on `shrublab-assets` and
`cache.shrublab.xyz` on `nix-cache`. The pinned provider cannot import an existing
[R2 custom domain](https://github.com/cloudflare/terraform-provider-cloudflare/blob/v5.26.0/docs/resources/r2_custom_domain.md).
Their adoption therefore requires the operator's approved brief deletion and
recreation of those two domain bindings, not of either bucket.

The backend's `tofu-state` bucket is not part of the supplied bucket inventory
and is not adopted or recreated by this change. Its backend configuration is
unchanged.

## Migration

Do not apply either new root against the old combined state.
Follow [the state split and adoption runbook](../../docs/runbooks/cloudflare-split.md)
first. API scopes, backend access, acceptance and recovery are covered there.
