# Tasks

Implementation follows `design.md` and the four capability deltas. Dispatch one bounded writer task at a time and review stable checkpoints before overlapping edits. The parent owns expensive repository gates. Live/operator tasks below are not authorized by implementation approval and must remain unchecked until approved and evidenced.

Before any local `.#` evaluation after edits, satisfy the repository's Git-index precondition (`git add -A`), verify the relevant indexed content, and avoid reset/checkout/stash. Use `path:` only for the repository's documented fixture/copied-tree exceptions. Never decrypt or edit encrypted secrets; provide the operator with templates and required actions instead.

## 1. Provider-directory restructure with unchanged Kanidm behaviour

- [x] 1.1 Move the existing provider runtime, host-auth contributor and package-family helper into `modules/identity/kanidm/{server,host-auth,_packages}.nix`; update intrinsic imports and keep current aspect names and production selection. Update `CONVENTIONS.md` and the relevant architecture paths to allow cohesive multi-contributor feature directories without new discovery filters or `default.nix` wrappers. Verify with focused `bash tests/check-identity-contract-directionality.sh`, `bash tests/kanidm-restore-contract.sh` and evaluated provider/client release-family and host-auth settings; do not update unrelated structure inventories merely to match new paths.
- [x] 1.2 Remove copied client/secret inventories and unrelated fixed configuration snapshots encountered in `tests/check-identity-contract-directionality.sh:1-190`; retain/refocus subset and dependency-direction behaviour with small independent fixtures. Verify the focused suite passes and a fixture that improperly couples a remote client to local server options fails for that intended reason. Document what the suite proves rather than asserting complete live compatibility.

## 2. Explicit common policy and intrinsic OIDC realization

- [x] 2.1 Replace the shared `policy/identity.json:1-164` shape with `policy/identity.nix` common registration intent and explicit provider extensions; derive route-owned facts once and preserve callbacks, public/confidential posture, group-dependent permissions and credential identity. Project that policy into retained Kanidm provisioning, including registrations for external/deselected clients. Verify the focused identity suite against representative restricted-group, group-claim, private/extra-callback and external-client cases; reject missing clients, unknown groups and unsupported permission translation by name. Remove the superseded shared document and update its documentation/references in this task.
- [x] 2.2 Extract Kanidm's pure `_client.nix` projection and evolve `modules/identity/_oidc.nix` into the typed, read-only provider-neutral shape, including a key-set output when used by Cloudflare. Keep declarations and realization together unless a real participant needs a split. Verify with focused `nix eval` fixtures that a remote client resolves without provider units/options, a changed route changes derived endpoints, and a client import cannot provision the server; update interface documentation and its behavioural tests here.
- [x] 2.3 Replace provider-specific OIDC construction/scopes in affected application and host bindings with intrinsic outputs and only the application adapters actually needed. Preserve provider slugs/callbacks that affect account linkage; keep explicit runtime secret-delivery contracts and SOPS readership. Verify focused evaluations for the differing consumer surfaces (Paperless/Homarr group mapping, Memos credential file, Langfuse signing, generic discovery and Cloudflare external client), then run the identity suite. Write the per-application acceptance/rollback matrix in the identity runbook in this task; do not claim live account continuity from evaluation.

## 3. Retained Kanidm host-access boundary

- [x] 3.1 Decouple `kanidm/host-auth.nix` from the active OIDC `providerUrl` (the existing coupling is at `modules/identity/kanidm-host-auth.nix:35-39`) and bind retained Kanidm runtime/host clients to their independently identified policy route. Keep current URI, Unix identities, allowlists and package family unchanged until an alternate route is approved. Verify a focused policy fixture switching application OIDC to Authentik leaves Kanidm host-auth URI and group policy unchanged; run the identity and Kanidm restore suites. Add the endpoint/domain/TLS/trust acceptance and break-glass procedure to the runbook.
- [x] 3.2 Provide explicit composition for retaining the Kanidm server independently of the active application provider, without activating both merely through source discovery. Preserve its encrypted overlay, backup and fail-closed restore behaviour. Verify provider-only, host-client-only and temporary coexistence evaluations and `bash tests/kanidm-restore-contract.sh`; document that Kanidm retirement remains blocked on a separately accepted host-auth transition.

## 4. Pinned Authentik runtime and native provisioning

- [x] 4.1 Pinned `github:nix-community/authentik-nix` at `b34f78837a7992146e6bdd43c85d03601b3b7ad5` (upstream 2026.8.5) with `nixpkgs` following this flake. Verified by evaluation against the current lock: `nixosConfigurations.la-admin-1.config.services.authentik.authentikComponents.manage.name` resolves to `authentik-manage`, the module exposes server/worker/migrate units, `settings` rendered to `/etc/authentik/config.yml`, a `blueprints_dir` override and an `environmentFile` for secrets, and it can be told not to own a cluster (`createDatabase = false`). No Authentik component has been built, so the build half of the original gate is unverified and no container fallback is needed until it is.
- [x] 4.2 Implement `modules/identity/authentik/server.nix` and the selected-provider composition on LA as an explicitly opt-in candidate with separate state and policy-bound listener. Register its PostgreSQL consumer through the existing declaration contract and keep readiness local. Verify candidate `nix eval`/build using the pinned integration shows server and worker wired to the declared database, while current production defaults and remote consumer hosts gain no Authentik units. Add native-runtime failure notification and operational documentation with this slice.
- [x] 4.3 Add explicit provider/client runtime secret bindings and plaintext bootstrap templates for Authentik's stable secret key, administrative bootstrap, database, SMTP/signing requirements and client credentials. Reuse `lib/secrets.nix`; do not infer file readership from route placement or change encrypted files. Verify evaluated runtime paths, permissions, worker access and restart/reload behaviour cover each consumed secret without plaintext store content or diagnostics. Document operator bootstrap order and exact secret ownership; validate with the focused secret/identity checks rather than copying a credential inventory into tests.
- [x] 4.4 Implement generated Authentik registrations and `_client.nix` from shared policy, in `blueprints.nix` for delivery and `_blueprint.nix` for the pure document. Entries declare only the fields Nix owns (groups, providers, applications, access bindings), reference upstream default flows, stages and scope mappings by `!Find`, and carry credentials as `!Env` names — never values. Verified structurally: the rendered document parses with a real YAML parser (`yq`) and entry counts follow policy (one provider and application per client, one binding per allowed group, plus the groups scope mapping only when a client releases group names). Actual apply, allowed/denied login and claim shape remain operator checks (6.2, 6.3) because they need a live provider. Consumers also dropped their provider-named identifiers: Paperless' `provider_id`, Tududi's `OIDC_PROVIDER_SLUG`, Memos' provider `uid` and its `memos-idp-<client id>.json` label, and the two callback paths that embed a slug all derive from the client id, which is the policy key both providers provision under (a separate override was removed: it reached only the client contract, so registering under it would desynchronise), and a suite check fails when a callback path stops carrying its own client id.
- [x] 4.5 Declared the flows Nix owns and left the rest to Authentik's defaults: an invitation-gated enrollment flow (`_enrollment.nix` — invitation stage with `continue_flow_without_invitation: false`, credential and detail prompts, `userwritestage` creating the person in the policy's enrollment group, `userlogin`), plus a brand keyed to the identity host (`_brand.nix`) and the seed roster (`users`, `state: created`, no credential). Verified structurally: the rendered document parses, the roster, enrollment and brand entries carry the policy's values, and a roster naming an undeclared group fails rendering by name. Authentication, authorization, invalidation, recovery and user-settings flows remain Authentik's defaults, referenced by slug; live apply, invitation acceptance, membership persistence and retirement remain operator checks (6.2).
- [x] 4.6 Register the provider with the substrate's export-first database dump and with `state-backups` for `/var/lib/authentik`, and document that recovery is database plus assets plus the stable secret key, restored into an isolated target. The stable secret key and bootstrap credentials are documented as the recovery set in `docs/runbooks/authentik-secrets.md`. A restore has not been exercised: it needs the live database (6.2).

## 5. Cloudflare projection and repository integration

- [x] 5.1 Keep the Cloudflare Access IdP in `opentofu/cloudflare/config.auto.tfvars:4-8` as the infrastructure input, but gate it: the identity suite now resolves the `cloudflare-access` client from policy and fails when the declared name, authorization URL, token URL or key-set URL drift from it. Chosen over a generation pipeline because a generated tfvars artifact would need its own formatting/freshness gate for four derived strings, while the check gives the same single-authority guarantee. Preserve the existing secret-runtime rendering boundary and the `groups` Access-rule meaning; production selection stays unchanged pending acceptance, and no infrastructure is applied.
- [x] 5.2 Recorded the rationale in `docs/decisions.md` (D-115), updated `ARCHITECTURE.md`, `STRUCTURE.md`, `CONVENTIONS.md`, `docs/architecture.md` and the two identity runbooks alongside the boundaries they describe, and removed the superseded application-only wiring (`policy/identity.json`, the Kanidm-shaped policy reads, and the provider-named scopes, labels and enable-option text in Paperless, Homarr, Karakeep, Langfuse, Tududi, Memos and Grafana — each now derives from the client contract). Three suite assumptions failed as a direct consequence and were corrected rather than relaxed: the geopulse contract's missing-cluster probe declares no instance instead of relying on a host that serves no database, the Homarr scope check asserts the contract's scope behaviour (unquoted, unique, group scope present) instead of one provider's ordering, and the scaffold contract checks that every private-transport route has its front instead of pinning the exact front inventory. Gates on the final tree: `treefmt --fail-on-change`, `just checks all` (24 contract entries), `nix flake check --no-build --all-systems`. Live claims stay pending in section 6.

## 6. Operator-gated staging and application acceptance

- [ ] 6.1 Obtain explicit staging approval, the staging URL, SMTP/bootstrap/signing/client secret inputs and operator-applied SOPS preparation. Preserve base-system access before enabling secret-dependent runtime; if any new host reader is needed, add its recipient only through the operator's approved process. Deploy the isolated candidate only after approval. Verify server/worker/database health and successful blueprint instances without changing the canonical production route; record commands and observed outcomes in the runbook acceptance record.
- [ ] 6.2 With operator-controlled test identities, verify invitation delivery/enrollment restriction, authentication, recovery and UI-owned membership persistence across reapply. Complete an isolated backup/restore login with required secret/signing material. Verify allowed and denied access against the actual selected release. Record evidence; leave any unavailable mail, recovery or restore check explicitly pending.
- [ ] 6.3 Accept every affected application's existing-account continuity and authorization using the runbook matrix, including any UI-owned provider setup and Cloudflare test federation. Verify data/roles, subject/linkage, callbacks, signing, group claims and the supported rollback after backing up affected application state. Record each application's result; matching email/client ID/secret or an empty new account is not acceptance. Use explicit temporary candidate overrides only where necessary and document their removal.

## 7. Operator-gated cutover and closeout

- [ ] 7.1 Confirm host access no longer depends on Kanidm before the application cutover: `kanidm-host-auth` is deselected on both hosts, so host login is Tailscale SSH plus the static `sshd` keys. Verify Tailscale SSH and a key-based `ssh` session from independent sessions on `la-admin-1` and `oci-melb-1`, and keep a console path on each until they are verified after the switch. No retained Kanidm compatibility endpoint is required; record the retirement and the rollback (moving `provider` back redeploys the retained server from untouched state).
- [ ] 7.2 Obtain explicit cutover approval and review the exact coordinated application/provider/Cloudflare changes. Back up both identity and affected application state; apply only the approved identity infrastructure scope, keeping the IdP outside its own Access gate. Verify discovery/JWKS, application allowed/denied logins, existing accounts, Cloudflare access and retained host login immediately after switching; execute the recorded rollback if acceptance fails.
- [ ] 7.3 After operator acceptance and an agreed observation window, remove temporary application test overrides and obsolete application-SSO migration wiring no longer required by rollback. Retain Kanidm compatibility state, server, secrets/backups and host clients while still required. Verify the focused identity/restore checks and parent integration gates, update the acceptance record and document the separate host-auth retirement condition. Do not mark this change fully accepted while any required operator task remains unverified.

## 8. Email-code verification and passkeys

- [x] 8.1 Replace link-based email ownership verification with a shared native code stage for enrollment, login and signed-in re-verification. Consume only address-bound confirmed proof, keep enrollment inactive until success, and remove superseded link wiring. Verify proof-policy behaviour and rendered flow relationships; record native resend limitations.
- [x] 8.2 Enable passkey setup with discoverable credentials and user verification, and conditional passwordless sign-in alongside username-or-email password fallback. Validate the rendered blueprint and focused identity contracts without changing application-provider selection.
- [ ] 8.3 Implementation gates passed (`just checks all`, exit 0; proof-policy and pinned-serializer checks). Remaining: deploy, then obtain deployment acceptance: correct/incorrect codes, address changes, repeated login without email MFA, passkey enrollment and fresh passwordless sign-in. Do not equate blueprint success with browser acceptance.

## 9. Mobile brand appearance

- [x] 9.1 Remove mobile theme background overrides that obscure the dashboard's native wallpaper; verify a mobile-width headless fixture with the pinned frontend CSS stops painting the flow fallback over the dashboard, and build the resulting blueprint.
- [ ] 9.2 After deployment, confirm the dashboard wallpaper and tint on a mobile browser, and confirm login/enrollment backgrounds remain visible.

## 11. Login form

- [x] 11.1 Merge username and password into one identification form by binding the flow's password stage on the identification stage, enable the "Remember me on this device" toggle and the password reveal, and remove the manual padding from the flow title now that the heading is centred by CSS. Verified by building the rendered blueprint: the identification entry carries `password_stage`, `enable_remember_me` and the passkey stage, and the password entry carries `allow_show_password`.
- [ ] 11.2 After deployment, confirm in a browser that a password manager offers and saves the credential on one form, that a passkey sign-in still completes without a password, and that an unverified address still stops at the email code stage.

## 10. Launcher visibility

- [x] 10.1 Hide the Cloudflare Access application through Authentik's native `meta_hide`, retaining its provider and policy bindings; verify the field against the pinned model and build the blueprint.

## 12. Focused glass theme

- [x] 12.1 Replace the fetched Glassmorphism base and appended overrides with one tracked stylesheet. Preserve translucent surfaces, rounded controls, wallpaper tint, branding and dashboard artwork sizing; use native Authentik layouts, background layers and component variables. Keep upstream attribution for adapted styling. Remove obsolete theme plumbing and document ownership.
- [x] 12.2 Validate the assembled theme against the pinned frontend at mobile and desktop widths: login, recovery/enrollment, dashboard wallpaper/logo, keyboard focus and profile-menu hit-testing. Record what was exercised; deployment and operator visual acceptance remain separate.

- [x] 12.3 Replace filled text controls with underlines and pinned upstream Maple Mono italic. Hide only the combined login title and visual field labels, retaining accessible names, other flow titles and native password interaction.
- [x] 12.4 Verify real font delivery, accessible field names, underline focus/error feedback, title isolation and mobile/desktop rendering. Deployment acceptance remains separate.

Chromium checks at 390×844, 1440×1000 and 2000×970 covered the initial refined login:
borderless neutral frost, narrower desktop form, working password visibility toggle, visible
keyboard focus and distinct invalid-field styling. Recovery, closed invitation-gated enrollment,
the native mobile application list and desktop grid also render without horizontal overflow.
Wallpaper and logos load, and hit-testing the open profile menu reaches its sign-out link above
the application content. Remember-me placement remains native: CSS reordering would disagree
with keyboard order; moving it requires a frontend markup change.
The browser substitutes only the assembled CSS in flow documents; dashboard identity and
application APIs use read-only fixtures and the evaluated brand settings. No brand was changed
through the API and no credentials were submitted. Enrollment beyond the invitation gate,
passkey ceremonies and other browser engines remain untested.

All three host derivations evaluate and OpenSpec validation passes. The focused identity check
assembles the blueprint and passes email-proof behaviour, then fails its stale requirement for
`--ak-flow-background`; that assertion and the earlier music-enable expectation remain deferred
at the operator's request. The final focused browser, formatting, oci-melb-1 host evaluation
and OpenSpec validation run passed. Full-suite cleanup and live deployment acceptance remain
separate and are not claimed by these two completed theme tasks.

The underlined-field revision passes Chromium checks at 390×844 and 1440×1000. The pinned
Maple Mono italic WOFF2 returns HTTP 200 and loads as a browser font. Accessible field names,
visible remember-me text, focus/error underlines and password visibility toggling remain intact.
The combined login heading is hidden; recovery and enrollment titles remain visible. Previews
are `/tmp/shrublab-lines-390.png` and `/tmp/shrublab-lines-1440.png`. Formatting,
oci-melb-1 toplevel evaluation and strict OpenSpec validation also pass. No deployment or live
brand edit was performed; stale-suite cleanup remains deferred.

- [ ] 12.5 Trial Poiret One with brighter field text, `1.1rem 0.6rem 0` padding, a slimmer/taller panel and extra vertical spacing, a toggle-styled remember-me left in place, a full-viewport frosted panel on narrow screens, and reduced-motion-aware focus/placeholder transitions. CSS only; no frontend patch.

## Workflow follow-up

- Review and archive only after tracked implementation and approved live acceptance are complete. If live work is intentionally deferred, leave those tasks unchecked and report implementation-ready versus deployment-accepted status separately.
- A future host-auth replacement/removal is a separate decision/change; it must remove remaining compatibility wiring and state only after its own acceptance and retention requirements are satisfied.
