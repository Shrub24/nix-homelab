# Baseline: make-oidc-contract-intrinsic

Captured before any mutation, at the start of implementation. Host evaluations use
`nix eval --no-write-lock-file`; config observables use `--json --apply`.

## 1. Host toplevel drvPaths

| host | toplevel drvPath |
| --- | --- |
| `oci-melb-1` | `/nix/store/mbk6mzp1zsm7fh5bk7f05in398klxgx3-nixos-system-oci-melb-1-26.11.20260813.0e251e2.drv` |
| `la-admin-1` | `/nix/store/31spnn180mr63rfk4w2mlb9fjdp4yqn9-nixos-system-la-admin-1-26.11.20260813.0e251e2.drv` |
| `home-forge` | `/nix/store/8bwp1h8lxdp1xxd8bwdyvijrswkfzn5b-nixos-system-home-forge-26.11.20260813.0e251e2.drv` |

## 2. Coupling evidence

### 2.1 The provider's OIDC mirror has zero readers

```
$ grep -rn 'identity\.kanidm\.oidc' modules/ tests/
modules/identity/kanidm-runtime.nix:389:          identity.kanidm.oidc = {
```

One hit, and it is the writer. No module or test reads `services.identity.kanidm.oidc.*`.

### 2.2 The Kanidm release family is pinned in three places

```
$ grep -rn 'kanidm_1_11\|kanidmWithSecretProvisioning' modules/ tests/
modules/identity/kanidm-host-auth.nix:32:          package = lib.mkDefault pkgs.kanidm_1_11;
modules/identity/kanidm-runtime.nix:396:            package = pkgs.kanidmWithSecretProvisioning_1_11;
modules/identity/kanidm-runtime.nix:444:        environment.systemPackages = [ pkgs.kanidm_1_11 ];
```

### 2.3 `mkOidcEndpoints` is defined once and called nowhere

```
$ grep -rn 'mkOidcEndpoints' lib/ modules/ tests/
lib/policy.nix:24:  mkOidcEndpoints = issuerUrl: {
```

Repo-wide (excluding `.git`, `.jj`, `.qmd`, and the change artifacts) the same single
definition is the only occurrence.

**Its derivation is not equivalent to the one in use.** `lib/policy.nix:24-30` takes an
issuer base and returns `<issuer>/authorize`, `<issuer>/api/oidc/token`,
`<issuer>/api/oidc/userinfo` — the Pocket ID endpoint shape the requirement was written
against. The identity contract (`modules/identity/identity-oidc.nix:25-32`) emits Kanidm's
shape, where authorization and token are provider-level and only issuer/wellknown/userinfo
are client-relative:

| field | `lib/policy.nix` helper | identity contract (resolved below) |
| --- | --- | --- |
| `issuerUrl` | `issuerUrl` | `https://id.shrublab.xyz/oauth2/openid/<client>` |
| `wellknownUrl` | `<issuer>/.well-known/openid-configuration` | `<client issuer>/.well-known/openid-configuration` |
| `authorizationUrl` | `<issuer>/authorize` | `https://id.shrublab.xyz/ui/oauth2` |
| `tokenUrl` | `<issuer>/api/oidc/token` | `https://id.shrublab.xyz/oauth2/token` |
| `userinfoUrl` | `<issuer>/api/oidc/userinfo` | `<client issuer>/userinfo` |

The helper also emits no `clientId`, and its two provider-level outputs cannot be expressed
as a function of the issuer base alone. Task 2.2 was therefore not performed; see the report.

### 2.4 Scaffold check `7l-6` pins the missing-namespace failure

`tests/check-dendritic-scaffold-contract.sh:1294-1309`:

```
# 7l-6. Deleting the OIDC contributor removes OIDC behavior/eval while the
# sibling kanidm contributor still publishes identity-client. Detection is the
# missing services.identity.oidc option (eval failure), never a publication.
D="$(make_copy)"
rm "$D/modules/identity/identity-oidc.nix"
[ "$(pub_names_of "$D" | grep -c 'identity-client')" -ge 1 ] || fail "7l-6: sibling contributor must still publish identity-client after OIDC deletion"
oidc_out="$(nix eval ... "path:${D}#nixosConfigurations.oci-melb-1.config.system.build.toplevel.drvPath" 2>&1)"
[ "$oidc_rc" -ne 0 ] || fail "7l-6: deleting the OIDC contributor must break OCI identity eval"
case "$oidc_out" in
  *"services.identity.oidc' does not exist"*) ;;
  *) fail "7l-6: expected missing services.identity.oidc, got: ..." ;;
```

Related: `7l-5` (`:1283-1292`) injects `aspects.identity-client` into the forge record and
asserts `services.identity.*` becomes non-empty. Both legs are re-pointed by task 6.1.

## 3. Identity observables (equivalence baseline)

`providerUrl` and every endpoint below are identical on both hosts.

| observation | `la-admin-1` | `oci-melb-1` |
| --- | --- | --- |
| `services.identity.oidc.providerUrl` | `https://id.shrublab.xyz` | `https://id.shrublab.xyz` |
| `clientPathPrefix` | `https://id.shrublab.xyz/oauth2/openid` | same |
| `tokenUrl` | `https://id.shrublab.xyz/oauth2/token` | same |
| `clients` key set | `beszel`, `cloudflare-access`, `karakeep`, `paperless`, `termix` | same |
| `hostAuth.enable` / `sshIntegration` / `pamAllowedLoginGroups` | `true` / `true` / `[ "admins" ]` | same |
| `services.kanidm.package` | `…-kanidm-with-secret-provisioning-1.11.0.drv` (`/nix/store/9q9ljyww1iqxnfzychqqqd0p2hcjl0q0-…`) | `…-kanidm-1.11.0.drv` (`/nix/store/s1vcm7nxr4sg0alnzcqmnflawvf19lri-…`) |
| kanidm entries in `environment.systemPackages` | `kanidm-1.11.0.drv` (`/nix/store/9a8klz71d6igpq23bd49cczsh7skxc3x-…`), `kanidm-with-secret-provisioning-1.11.0.drv` ×2 | `kanidm-1.11.0.drv` ×2 (`/nix/store/s1vcm7nxr4sg0alnzcqmnflawvf19lri-…`) |

Per-client endpoints (all five clients, both hosts):

| client | `clientId` | `issuerUrl` | `wellknownUrl` | `authorizationUrl` | `tokenUrl` | `userinfoUrl` |
| --- | --- | --- | --- | --- | --- | --- |
| `beszel` | `beszel` | `…/oauth2/openid/beszel` | `…/beszel/.well-known/openid-configuration` | `…/ui/oauth2` | `…/oauth2/token` | `…/beszel/userinfo` |
| `cloudflare-access` | `cloudflare-access` | `…/oauth2/openid/cloudflare-access` | `…/cloudflare-access/.well-known/openid-configuration` | `…/ui/oauth2` | `…/oauth2/token` | `…/cloudflare-access/userinfo` |
| `karakeep` | `karakeep` | `…/oauth2/openid/karakeep` | `…/karakeep/.well-known/openid-configuration` | `…/ui/oauth2` | `…/oauth2/token` | `…/karakeep/userinfo` |
| `paperless` | `paperless` | `…/oauth2/openid/paperless` | `…/paperless/.well-known/openid-configuration` | `…/ui/oauth2` | `…/oauth2/token` | `…/paperless/userinfo` |
| `termix` | `termix` | `…/oauth2/openid/termix` | `…/termix/.well-known/openid-configuration` | `…/ui/oauth2` | `…/oauth2/token` | `…/termix/userinfo` |

(`…` = `https://id.shrublab.xyz`.)

### 3.1 Consumer-side OIDC values

`oci-melb-1`:

```json
"paperlessOidc": {
  "clientId": "paperless",
  "enable": true,
  "wellknownUrl": "https://id.shrublab.xyz/oauth2/openid/paperless/.well-known/openid-configuration"
},
"karakeepOidc": {
  "allowDangerousEmailAccountLinking": false,
  "autoRedirect": true,
  "clientId": "karakeep",
  "disablePasswordAuth": true,
  "enable": true,
  "providerName": "Kanidm",
  "scope": "openid email profile",
  "wellknownUrl": "https://id.shrublab.xyz/oauth2/openid/karakeep/.well-known/openid-configuration"
}
```

`la-admin-1`: `paperlessOidc` and `karakeepOidc` are `null` (neither workload is placed
there). `termixOidc` is `null` on **both** hosts — the `termix` aspect is not selected
anywhere, so its consumer wiring is not evaluable from a host configuration; task 4.3 only
changes its prose.

### 3.2 Selected aspects

| host | aspects |
| --- | --- |
| `la-admin-1` | `base` `beszel` `builder-access` `cache-publisher` `edge` `fleet-packages` `gatus` `homepage` `identity-client` `identity-provider` `internal-contracts` `networking` `notify` `observability-agent` `oci-images` `provenance` `push-server` `shell` `state-backups` `tailscale` `vaultwarden` `webhook` `web-policy` |
| `oci-melb-1` | `ai-gateway` `base` `builder-access` `cache-publisher` `cockpit` `edge` `fleet-packages` `identity-client` `internal-contracts` `karakeep` `networking` `niks3-cache` `notify` `observability-agent` `oci` `oci-images` `paperless` `phoenix` `postgres` `provenance` `shell` `state-backups` `tailscale` `web-policy` |
| `home-forge` | `base` `builder-access` `cache-publisher` `dj` `fleet-packages` `internal-contracts` `music` `networking` `notify` `observability-agent` `oci-images` `omniroute` `postgres` `provenance` `shell` `state-backups` `tailscale` `web-policy` |

### 3.3 SOPS secret names (readership baseline)

`la-admin-1`: `beszel_agent_key` `beszel_agent_token` `cloudflare_dns_api_token`
`homepage_beszel_password` `homepage_beszel_username` `homepage_navidrome_salt`
`homepage_navidrome_token` `homepage_navidrome_user` `homepage_slskd_key`
`homepage_tailscale_api_key` `homepage_tailscale_device_id` `host_recovery_rescue_password_hash`
`host_ssh_identity_raw` `kanidm_admin_password` `kanidm_idm_admin_password`
`kanidm_oauth2_beszel_basic_secret` `kanidm_oauth2_cloudflare-access_basic_secret`
`kanidm_oauth2_karakeep_basic_secret` `kanidm_oauth2_paperless_basic_secret`
`kanidm_oauth2_termix_basic_secret` `kanidm_provisioning_overlay` `niks3_api_token`
`notification-daemon/ntfy_token` `notification-daemon/telegram_bot_token` `ntfy-firebase-key`
`ntfy/auth` `state_backups_restic_password` `state_backups_s3_access_key_id`
`state_backups_s3_secret_access_key` `tailscale_auth_key` `vaultwarden_admin_token`
`vaultwarden_push_installation_id` `vaultwarden_push_installation_key`
`vaultwarden_smtp_password` `vaultwarden_smtp_username`

`oci-melb-1`: `beszel_agent_key` `beszel_agent_token` `bifrost_deepseek_api_key`
`bifrost_encryption_key` `bifrost_gemini_api_key` `bifrost_opencode_api_key`
`bifrost_openrouter_api_key` `cockpit_service_user_password_hash`
`host_recovery_rescue_password_hash` `host_ssh_identity_raw`
`karakeep_asset_store_s3_access_key_id` `karakeep_asset_store_s3_secret_access_key`
`karakeep_meilisearch_master_key` `karakeep_nextauth_secret` `karakeep_oidc_client_secret`
`niks3_api_token` `niks3_s3_access_key_id` `niks3_s3_secret_access_key` `niks3_signing_key`
`notification-daemon/ntfy_token` `notification-daemon/telegram_bot_token`
`paperless_admin_pass` `paperless_gpt_api_token` `paperless_oidc_client_secret`
`paperless_secret_key` `state_backups_restic_password` `state_backups_s3_access_key_id`
`state_backups_s3_secret_access_key` `tailscale_auth_key`

## 4. Post-change delta (gates for tasks 2.1-2.4, 3.1-3.2)

### 4.1 Toplevel drvPaths moved, and the cause is provenance

| host | baseline | after the change |
| --- | --- | --- |
| `oci-melb-1` | `mbk6mzp1zsm7fh5bk7f05in398klxgx3` | `m7dwma72qm2biqf0fq97f65pcv10qq9n` |
| `la-admin-1` | `31spnn180mr63rfk4w2mlb9fjdp4yqn9` | `mgb5daxhp7smyrf87l1vaqhwlfi8w30y` |
| `home-forge` | `8bwp1h8lxdp1xxd8bwdyvijrswkfzn5b` | `l3hishlh83wxqxdylp4s45i57s5hqg3v` |

All three moved, including `home-forge`, which selects no identity aspect and no identity option.
The cause is the provenance module, not the identity change: `modules/flake/provenance.nix:15`
publishes the tracked tree (`environment.etc."nixos-source".source = self.outPath`), so every tracked
edit changes the `/etc` derivation, then `activate`, then the toplevel.

Evidence for `oci-melb-1`: the two toplevel derivations have identical input-derivation *name* sets,
and the only content differences are

1. the toplevel drv/out hash (consequence),
2. `etc.drv` `cv4gxlb71m45zfih3nhgrz3v8clrajz4` -> `k2l7wnahbmfyg1mp48hddrs85clp3n0p`,
3. `activate.drv` `66sb0xb6gy789d80sf98p4q83n9rc6dx` -> `05rvw91ya3py6638qah8cqgr0cn6cy7c`, including the
   `…-etc/etc` symlink target rewritten inside its build command.

Diffing the two `etc.drv`s leaves exactly one content change: the published source copy
`z6b1r9yn0s6zca5iiqdplm3pra8nf544-source` -> `n5h9kxfi9hm5hai9yndp3iiqnvdjbivq-source`. Their
`inputSrcs` and input-derivation name sets are identical. No service, unit, package, kernel, initrd,
secret path, or check derivation changed.

### 4.2 Identity observables are unchanged

The section-3 expression, re-evaluated after the change and diffed against the baseline captures:
`la-admin-1` **IDENTICAL**, `oci-melb-1` **IDENTICAL** across `providerUrl`, `clientPathPrefix`,
`tokenUrl`, all five clients with all five endpoints each, `hostAuth` values,
`services.kanidm.package`, the kanidm system packages, the paperless/karakeep OIDC values, and the
SOPS secret name sets.

### 4.3 Provider-only subset (task 2.4)

Scratch copy outside the repository with the `kanidm-host-auth` selection removed from
`la-admin-1` **and** the host fragment's own `identity.hostAuth = { … }` assignment removed. The
second removal is required, not optional: the host fragment assigns options the capability owns, so
with the capability absent the assignment itself fails on the missing namespace — the same
select-then-assign coupling this change removes for the projection.

```
toplevel drvPath        /nix/store/pik1zfqrfalccn98ckhcx14mym83h2nm-nixos-system-la-admin-1-26.11.20260813.0e251e2.drv
providerUrl             https://id.shrublab.xyz
oidcClientKeys          beszel, cloudflare-access, karakeep, paperless, termix
identityNamespaces      [ "kanidm", "oidc" ]      (no hostAuth namespace)
hostAuthPresent         false
kanidmServerEnable      true
kanidmUnixEnable        false
provisionEnable         true
kanidmPackage           /nix/store/9q9ljyww1iqxnfzychqqqd0p2hcjl0q0-kanidm-with-secret-provisioning-1.11.0.drv
oauth2SecretSourceKeys  beszel, cloudflare-access, karakeep, paperless, termix
```

Deviation from the stated expectation: `tasks.md` 2.4 asks for `services.identity.hostAuth.enable ==
false`; the namespace does not exist at all in that composition, so the observable is its absence
rather than a false flag.

## 5. Anchors for the follow-up packets

Task 4.3 (consumer prose): `modules/admin/termix.nix` lines 2, 4, 31, 33.

Tasks 6.1-6.4 (test anchors): `tests/check-dendritic-scaffold-contract.sh` lines 513, 533, 581,
619, 620, 624, 626, 738, 891, 896, 898, 1238, 1283, 1287, 1292, 1295, 1299, 1300, 1314, 1317,
1318, 1541; `tests/check-identity-contract-directionality.sh` lines 162, 209, 210, 215, 222, 223,
231, 239, 264, 265, 424, 437, 1088.

Task 7.2 (live documentation): `ARCHITECTURE.md:56`; `STRUCTURE.md:81, 86, 87`; `CONVENTIONS.md:29`;
`docs/architecture.md:100`; `docs/plan.md:198`. Historical and to be annotated only:
`docs/decisions.md:983, 1032`; `docs/context-history.md:117`; `docs/dendritic-transition-analysis.md:20`.

Current expected suite state after this packet (both pin the retired contract):

- `tests/check-dendritic-scaffold-contract.sh` -> rc 1, first failure at the publication inventory
  ("discovered publications drifted …", the expected list still naming `flake.modules.nixos.identity-client`).
- `tests/check-identity-contract-directionality.sh` -> rc 1, first failure `AssertionError:
  identity-client selection anchor drifted` (the LA mutation script, line 222).

## 6. Post-change delta (consumer wiring and the Kanidm release family)

### 6.1 Equivalence

The section-3 expression, re-evaluated after the consumer wiring moved and the helper
changed: `la-admin-1` **IDENTICAL**, `oci-melb-1` **IDENTICAL** across `providerUrl`,
`clientPathPrefix`, `tokenUrl`, all five clients with all five endpoints each, `hostAuth` values,
`services.kanidm.package`, the kanidm system packages, the paperless/karakeep OIDC values, and the
SOPS secret name sets. The three toplevel drvPaths moved, which is expected and is not evidence:
`modules/flake/provenance.nix:15` publishes the tracked tree, so any tracked edit moves `/etc`.

### 6.2 Consumer-only composition (task 4.5)

Scratch copy outside the repository, `oci-melb-1` with `aspects.kanidm-host-auth` removed **and**
the host fragment's own `identity.hostAuth` assignment removed, so the only identity participants
are the importing consumers:

```
toplevel drvPath   /nix/store/g9nx5jn2nz4sivr5fc27psan9cggr014-nixos-system-oci-melb-1-26.11.20260813.0e251e2.drv
providerUrl        https://id.shrublab.xyz
identityNamespaces [ "oidc" ]                  (no hostAuth, no provider namespace)
kanidmClientEnable false   kanidmUnixEnable false   kanidmSystemPackages []
paperlessOidc      { clientId = "paperless"; enable = true; wellknownUrl = "…/paperless/.well-known/openid-configuration" }
karakeepOidc       { clientId = "karakeep";  enable = true; wellknownUrl = "…/karakeep/.well-known/openid-configuration"; … }
```

Both consumer records are byte-identical to the baseline values in section 3.1.

Observation, pre-existing and not introduced here: in a composition where nothing consumes
`services.kanidm.package`, the option resolves to nixpkgs' removed `pkgs.kanidm` alias and throws if
forced. `home-forge` behaves identically before and after (`forceable: false`), so the state follows
from the option's nixpkgs default rather than from this change.

## 7. Final validation on the change head (parent-owned battery)


Run at `@` on the change head after the test inversion, documentation and artifact alignment landed.
All three exit codes were captured explicitly (never through a pipe):

```
observables-rc=0   just-checks-rc=0   flakecheck-rc=0
just checks all  -> 18 suites, all PASS (incl. check-dendritic-scaffold-contract,
                    check-identity-contract-directionality, check-internal-contracts)
nix flake check --no-build .# -> all checks passed
```

Identity observables re-measured on the final tree, identical to section 3/6:

- `oci-melb-1` providerUrl=https://id.shrublab.xyz clients=beszel,cloudflare-access,karakeep,paperless,termix hostAuth={"enable": true, "pamAllowedLoginGroups": ["admins"], "sshIntegration": true} kanidm=kanidm-1.11.0.drv
- `la-admin-1` providerUrl=https://id.shrublab.xyz clients=beszel,cloudflare-access,karakeep,paperless,termix hostAuth={"enable": true, "pamAllowedLoginGroups": ["admins"], "sshIntegration": true} kanidm=kanidm-with-secret-provisioning-1.11.0.drv

- OCI consumer records: `{"clientId": "paperless", "enable": true, "wellknownUrl": "https://id.shrublab.xyz/oauth2/openid/paperless/.well-known/openid-configuration"}`,
  `{"allowDangerousEmailAccountLinking": false, "autoRedirect": true, "clientId": "karakeep", "disablePasswordAuth": true, "enable": true, "providerName": "Kanidm", "scope": "openid email profile", "wellknownUrl": "https://id.shrublab.xyz/oauth2/openid/karakeep/.well-known/openid-configuration"}`
- Toplevel drvPaths moved again, as expected: `environment.etc."nixos-source"` publishes the
  tracked tree, so every tracked edit moves `/etc` → `activate` → toplevel (D-057).
  Derivation equality is not evidence; the observables above are.
