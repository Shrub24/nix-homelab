# Cloudflare state split and bucket adoption

Configuration ownership is described in [Cloudflare](../../opentofu/cloudflare/README.md).
This runbook moves state ownership; it must not recreate existing service DNS,
Access applications, policies, identity providers, origin records or zone rulesets.

## Preflight

- Stop other Cloudflare plans/applies for the migration.
- Run from the repository root, using Fish. Keep the same shell for the commands below.
- Update the operator-managed token scopes for the existing resources, Workers R2
  Storage Read/Write, and the zone's Bot Management read/write access.
- Refresh credentials through the existing operator secret workflow. Do not put tokens
  in shell history or tracked files.
- Confirm the buckets listed in `opentofu/cloudflare/foundation/config.auto.tfvars`
  exist in the configured account and use the default jurisdiction. Do not delete buckets.
- Confirm both public domain mappings in that file.
- Check the existing `backend.hcl` still selects the current state bucket/key. It must
  not select the new foundation key.
- The existing backend names a `tofu-state` bucket not present in the supplied
  inventory. Resolve account/inventory access if initialization cannot reach it.

Initialize both backends without applying:

```fish
just tofu::init
just tofu::init --foundation
```

Confirm foundation has no managed resources (“No state file was found” is expected
on its first initialization). If it is already populated, stop and inspect it rather
than overwriting it. Confirm services still lists the old combined state:

```fish
tofu -chdir=opentofu/cloudflare/foundation state list
tofu -chdir=opentofu/cloudflare state list
```

## Split the combined state locally

Keep the snapshots private: state includes credentials.

```fish
set -l ROOT $PWD
umask 077

function split_cloudflare_state --argument-names state_dir
    tofu -chdir=opentofu/cloudflare state pull > "$state_dir/original.tfstate"
    or return 1
    cp "$state_dir/original.tfstate" "$state_dir/services.tfstate"
    or return 1

    tofu -chdir="$state_dir" state list -state=services.tfstate > "$state_dir/addresses.txt"
    or return 1
    while read -l address
        switch "$address"
            case 'cloudflare_dns_record.service[*' 'cloudflare_zero_trust_access_application.service[*'
                continue
        end
        tofu -chdir="$state_dir" state mv -state=services.tfstate -state-out=foundation.tfstate "$address" "$address"
        or return 1
    end < "$state_dir/addresses.txt"

    tofu -chdir="$state_dir" state list -state=services.tfstate
    or return 1
    tofu -chdir="$state_dir" state list -state=foundation.tfstate
end

set -l STATE_DIR (mktemp -d /tmp/cloudflare-split.XXXXXX)
and split_cloudflare_state "$STATE_DIR"
```

Record acceptance before pushing:

- Services contains only `cloudflare_dns_record.service[...]` and
  `cloudflare_zero_trust_access_application.service[...]`.
- Foundation contains all other original resource addresses, unchanged.
- The two lists are disjoint and their union is the original list.
- Keep `$STATE_DIR` and its automatic state-move backups until both applies are accepted.

Push foundation first, then services. Do not apply between the two pushes:

```fish
cd "$ROOT"
and tofu -chdir=opentofu/cloudflare/foundation state push "$STATE_DIR/foundation.tfstate"
and tofu -chdir=opentofu/cloudflare state push "$STATE_DIR/services.tfstate"
```

If either push fails, stop. Do not use `-force` or continue to apply.

## Adopt foundation additions

1. Delete only the two existing R2 custom-domain bindings in the dashboard:
   `assets.shrublab.xyz` and `cache.shrublab.xyz`. Retain both buckets and all
   contents. Schedule this short interruption away from builds and deployments.
2. Run:

   ```fish
   just tofu::apply --foundation
   ```

3. Review the confirmation before approving. Expect:
   - Imports of the ten existing buckets and existing Bot Management settings.
   - Creation of the two custom-domain bindings.
   - Bot Fight Mode off.
   - The retired cache hostname removed from the rate-limit exemption.
   - No bucket replacements, deletions or content operations.
   - No replacements of any migrated resource.
4. After the apply, confirm both R2 domains become active and serve existing objects.
   Record successful asset rendering and a known cache object's response.
5. Run `just tofu::apply`. It must read the foundation output and retain the existing
   service DNS and Access application identities. Review any changes against the
   committed web policy before approving.
6. Confirm foundation's rate-limit exemption includes `assets.shrublab.xyz` and
   `cache.shrublab.xyz`, and record that Bot Fight Mode is off.

## Recovery

If a state push fails, keep all applies stopped. Pull fresh remote snapshots from
both backends and compare them with `addresses.txt` and the original snapshot.
Finish the split so each original address has one owner before applying anything.

To reverse a split before the additions are applied, use native `tofu state mv`
with fresh local snapshots to move the original foundation addresses back into
services, then push both updated snapshots and restore the combined configuration
with jj. Do not force-push the older original snapshot over a newer state serial.

After bucket adoption or new domain creation, do not revert to the old combined
configuration without first accounting for the new resources. Keep the split and
repair forward. Never delete a bucket or state object to resolve a state conflict.

If domain recreation fails, reattach each domain to its original bucket in the
dashboard to restore delivery, then reconcile its ownership before another apply.
