# Identity

Application SSO is served by Authentik, the fleet's only identity provider. The Kanidm
implementation and its Unix/PAM/SSH capability were retired once the migration settled
(D-122), so host login is the operator account and its key.
`docs/runbooks/identity-migration.md` is the operator procedure; this document is the
mechanism behind it.

## Ownership split

| Concern | Authority |
| --- | --- |
| Approved clients, access groups, claim intent | `policy/identity.nix` |
| Client-side OIDC facts | `modules/identity/_oidc.nix` (intrinsic) |
| Provider registration | `modules/identity/authentik/server.nix` |
| People, credentials, memberships | Authentik's database and UI |
| Clients, groups, access bindings, brand and flow context | `modules/identity/authentik/_blueprint/document.nix` |
| Static flows, stages, prompts and policy expressions | `modules/identity/authentik/_blueprint/fragments/*.yaml`, assembled by `blueprints.nix` |

`identity-provider` binds the policy-selected provider and `authentik-identity` runs it.
Importing `_oidc.nix` resolves client
configuration and registers nothing: approving a client and deploying its application are
separate acts, and an application cannot register itself by being composed.

### Blueprint validation

The blueprint build validates literal values against `blueprints/schema.json` from the
selected Authentik package, using ruamel.yaml and python-jsonschema. The small adapter
preserves `!KeyOf`, `!Find`, `!Env`, `!Context` and `!Format` expressions and defers their value
validation; it neither resolves references nor reads credentials. Unknown tags fail.
Literal siblings still undergo schema validation. This checks document structure, not
whether database objects exist or whether a flow works in a browser. Runtime applicability
belongs to Authentik's importer. Editor custom-tag support recognises syntax but does not
infer the type of a resolved reference.

### Blueprint authoring

Static definitions are real YAML under `modules/identity/authentik/_blueprint/fragments/`.
Python expressions use block scalars. Nix projects fleet registrations and non-secret
context; `blueprints.nix` assembles them with the YAML fragments into one document using
ruamel.yaml. The fragment order lives in `_blueprint/document.nix`. Context supplies the enrollment
flow name, title, initial group and flow background. The editor header supplies schema
assistance; `.vscode/settings.json` declares expression tags. CI uses the packaged schema,
not the website copy.

Authentik applies entries in order:

- A `!KeyOf` reference resolves only against entries already applied, so an entry that points
  at a later one fails the whole blueprint. Keep definitions before their bindings; runtime
  applicability is checked by the importer.
- Groups are emitted parents-first: policy lists them in privilege order, which is the reverse
  of the order their nesting requires.
- Policy expressions are block literals in YAML. Multiline generated strings such as the
  vendored CSS are serialized as block literals by the build helper.
- A policy attaches to a stage binding through its own entry, `authentik_policies.policybinding`,
  because the binding model has no `policy` field. A `policy:` key on a binding is accepted as an
  unknown field and discarded, so the blueprint applies and the policy silently never runs.
- A field's declared shape is worth checking against the model before relying on it: an MFA
  enrolment attempt failed because `configuration_stages` on an authenticator-validate stage is a
  many-to-many to **Stage**, not to the `default-authenticator-*-setup` flows it looks like it
  should name.
- Undeclared entries are not reconciled away. A stage or binding deleted from the document stays in
  the provider until it is declared with `state: absent`, so every removal ships with a tombstone.
  Deleting a stage cascades its bindings, so the tombstone belongs on the stage.
- A **failed** apply leaves `status: error` that a byte-identical revert cannot clear: the worker
  compares file content, sees the previous good revision, and does nothing — not even on restart.
  Recovery is a real content change to the document (or an explicit apply), not a redeploy.

The blueprint applies independently of the server: the worker provisions while the UI may be
down, so a successful apply says nothing about HTTP readiness.

### Deployment gate

`authentik-blueprint-validate.service` is a provider-owned oneshot started during activation,
after the Authentik runtime and its migrations. It uses the runtime's dynamic user, state
directory and environment file; no API token or public route is involved. Changes to the
blueprint, rendered configuration or secret environment rerun it.

The gate requests upstream discovery, waits for instantiated upstream default/system
blueprints, and calls the pinned importer's `validate()` against the fleet document.
Validation performs database operations inside an always-rolled-back transaction; model
hooks are not claimed to be free of other side effects. The gate then requests an apply
through the upstream worker and requires a new successful result with the current SHA-512
content hash. A previously successful document is insufficient. The internal deadline is
300 seconds, with a 360-second systemd start timeout bounding the whole process. Rejection,
apply failure or timeout exits nonzero so activation can report failure.

The gate prints progress phases and a failure category, not serializer payloads that may contain resolved
credentials. The worker remains the application owner and has its own logging. Rolling
back the system generation does not undo blueprint changes already committed to the
database.

`checks.<system>.authentik-blueprint-tools` covers the static tag boundary. The isolated
gate harness (`tests/authentik-blueprint-delivery.nix`) exercises valid application, a
stale success hash, an invalid reference failing real activation and a stalled worker; it
needs a host with virtualisation and is run explicitly, not in the CI battery:

```sh
nix build --no-link --print-out-paths --impure --expr '
  let flake = builtins.getFlake (toString ./.); in
  import ./tests/authentik-blueprint-delivery.nix {
    pkgs = flake.inputs.authentik-nix.inputs.nixpkgs.legacyPackages.x86_64-linux;
    authentikModule = flake.inputs.authentik-nix.nixosModules.default;
  }'
```

Operational checks and recovery are in
[`runbooks/authentik-blueprints.md`](runbooks/authentik-blueprints.md).

The provider lives in a directory because runtime, provisioning, client projection and
assets cannot be understood apart. Inside it a non-underscore file is a discovered
contributor, and its `_blueprint/` folder holds the pipeline those contributors share: the
document generator, brand and theme sections, the YAML fragments, the assembler and the
activation gate.

## Which provider serves what

| Consumer | Provider | Endpoint source |
| --- | --- | --- |
| Applications (OIDC clients) | the policy's `provider` | the client contract, from the provider's `_client.nix` |

The provider publishes at `auth.shrublab.xyz`, served by that host's own TLS front
(`tailscale-serve` exposure) and deliberately outside Cloudflare Access — gating the
provider behind its own login is a lockout.

## Identifiers

The client id is the policy key. Paperless' `provider_id`, Tududi's callback slug, Memos'
provider `uid` and its `/etc/secrets` file label all derive from it, so a provider's name
reaches no consumer and a policy rename moves the identifier with it — at the cost of
orphaning an account linked under the previous value. There is no separate override,
because both providers provision under that key.

## Groups and administration

Group names are policy (`policy/identity.nix`); membership is provider state, edited in the
interface. Authentik groups nest, and a member of a group is an effective member of its
ancestors, so the fleet declares one chain and puts a person in the most privileged group
they need:

```
users  ←  service-admins  ←  admins  ←  superusers
```

- **`users`** — the root, and where invited enrollment places a new account.
  Every other group is beneath it, so an administrator also satisfies an access list that
  only asks for a confirmed person.
- **`service-admins`** — the user-facing applications read it for their own admin roles.
- **`admins`** — the operator-console clients read it (`grafana`, `beszel`,
  `cloudflare-access`). It does not reach the provider console.
- **`superusers`** — administers the identity provider. The flag is `is_superuser`, and it
  sits on this leaf deliberately: Authentik resolves a user's superuser status from *any*
  group in their ancestry, so carrying it higher would escalate every group below.

Authentik's own `authentik Admins` group stays empty except for `akadmin` and is the
break-glass route into the console. Its name is load-bearing upstream —
`authentik/recovery/lib.py` recreates `authentik Admins` with `is_superuser` set — so it is
not renamed; a fleet name for the same authority is declared instead.

The claim releases `request.user.all_groups()` rather than direct membership, which is what
makes the chain visible to applications. Authentik's default `groups` mapping uses direct
membership only, so a member of `superusers` would otherwise arrive at Grafana with no
`admins` claim at all.

The same mapping merges the application's own entitlements into `groups`, and emits them as
`entitlements` and `roles` as well. Entitlements are declared per application and resolved
against the user's whole ancestry, so they express per-application roles without adding a
group for every application — and because the mapping reads `provider.application`, a client
only ever receives its own. Merging into `groups` keeps clients that can only be told a
claim's contents, not its name, working unchanged.

Every user-facing client is provisioned with a `<client>-user` and `<client>-admin` role,
each bound to the least privileged group that should hold it — `users` and
`service-admins`, or `admins` where the client admits that group instead (Cloudflare
Access). An admin-only application declares no roles and keeps using the group names, and a
role is never bound to a group its own application does not admit, so declaring one cannot
widen access.

Roles (`authentik_rbac.role`) are permission bundles for object and system rights, needed
only by a machine account with scoped API access. The fleet has none, so no roles are
declared.

## Email verification

Authentik's default `email` scope mapping hardcodes `email_verified: false`, and its `User`
model stores no verification state. The fleet therefore declares `homelab-email`, whose
`email_verified` is true only while `user.attributes["email_verified_address"]` equals the
account's current address.

One expression policy records the current address when a confirmed email authenticator
belongs to that user and matches it. An already-confirmed address needs no new code or device.
Otherwise the native email setup stage sends a code and retains the confirmed authenticator.
The policy associates it with the sign-in stage, leaving the verification setup stage free
for a later address. Verification never activates a user or deletes an authenticator.
Devices for other addresses remain independent sign-in factors until the user removes them;
they cannot verify the current account address. `verify-email` is the signed-in entrypoint.

The code-entry UI is native, with no frontend fork. The setup stage has no resend cooldown
setting; a visible resend countdown and server-side issuance limit remain unimplemented.

Verification is a gate on login, not a prompt. One email stage is shared by three flows —
`enrollment`, `verify-email` and the upstream `default-authentication-flow`, where it is
bound at order 40, between the credential stages and the flow's own `user-login` stage at
order 100. Since only a login stage creates a session, an unverified person's plan halts at
the code stage and no session exists until the code is accepted; the accepting policy records
the address while retaining the confirmed device. A verified person's binding policy
fails, the stage is skipped, and login proceeds unchanged. The binding cannot instead hold two
policies, nor an unconditional recording policy, because it is evaluated once while the plan is
built, before a person is in context.
Verification decisions read the current database row rather than the flow's pickled user.
An address-less account fails closed: the login path sends it to verification like any other
unverified account, and the flow's own session policy refuses because no address can be proven.
Live state has two such rows and neither signs in through a browser flow — `AnonymousUser` and
the embedded outpost's service account — so the cost lands on an administrator or migration
that creates a person without an address, which blocks that person until one is set.
Invitation enrollment requires an address.

The code is entered in the initiating browser, preserving its flow plan and original
application destination even if mail is read on another device. There is no verification
link or cross-browser resumption. The gate withholds a new login session; an application-level
policy remains necessary to reject an existing session after its account's address changes.

An administrator who creates a person by hand is vouching for an address, not verifying it:
seeded and admin-created accounts stay unverified until they run the flow. See D-115 for the
rejected alternative (deriving the claim from `is_active`) and its consequences.

## Flows

| Flow | Purpose | Shape |
| --- | --- | --- |
| `enrollment` | invitation-gated self-registration | invitation → username/email → create active account without a usable credential → passkey or password setup → password only without a confirmed passkey → remaining email verification → guarded login → confirmation |
| `verify-email` | confirm an address for an existing account | current authenticated user → email code → login (records the address) → confirmation |
| `default-authentication-flow` | signing in (upstream, extended) | passkey, or password plus a required factor (passkey, email code or TOTP) → remaining email verification → login |
| `recovery` | interrupted signup or lost-credential recovery | identification → emailed link and confirmation → address-bound mailbox proof → strength-checked password → user write (`never_create`) → guarded login |

Email ownership verification uses codes; password recovery retains its upstream link mechanism.

The confirmation stage — an informational prompt with a Continue button — is shared by
`enrollment` and `verify-email`, so both end on the same screen instead of a bare redirect.
Both flows previously ended on a static redirect to the dashboard; that stage could not honour
`?next=`, which is why the confirmation replaces it.

Registration is closed: the enrollment flow stops without a valid invitation token, and an
invitation for an existing username fails because the flow creates the person.

The credentials step also refuses a name or an address that is already in use and says which,
on the form, instead of failing at account creation. Both comparisons are case-insensitive,
matching the login identification stage, which an exact-match check would not: `Foo` beside an
existing `foo` would sign in against the wrong person. The address check is a policy on the
prompt stage, so it is not atomic — two signups racing for one address can both pass, because
Authentik's user model carries no unique constraint on email.

## Installing the sign-in page

Authentik generates the dashboard's HTML at request time, so that page cannot carry a manifest and
the dashboard URL is not itself installable. The edge serves an install page beside it at
`https://auth.shrublab.xyz/pwa`: a manifest whose `start_url` is the dashboard and whose scope is
`/`, so an installed app opens at `/if/user/` and stays in its own window. Icons are rendered
from `assets/icon.svg` at build time — 192, 512, a maskable 512 for Android's adaptive mask, and
an `apple-touch-icon` — and the page carries the `apple-mobile-web-app-*` tags iOS reads.

The identity aspect declares these files and mounts them through `services.ingress.staticPages`;
the edge serves them ahead of the route's proxy handler without knowing which application is
behind it. Android installs from the page through the browser's install prompt, iOS through
Share → Add to Home Screen. Adding the dashboard itself to a home screen still gives a generic
icon on iOS, because iOS reads the tags of the page it was opened from.

## Passkeys and login identity

The login identification stage accepts username or email, case-insensitively, carries the
password-recovery link, and offers conditional WebAuthn through a dedicated passkey validator.
It also carries the password field itself, so username and password are one form: browsers and
password managers fill credentials when both fields are present in the same submit, which a
separate password page does not reliably get. A passkey assertion returns before the password
check and attaches the backend, so the flow's own password stage then skips itself, and the
stage's "Show password" reveal is enabled on that password stage.

Upstream authentication policies skip password and second-factor stages after successful
passwordless WebAuthn; email ownership verification still runs if required. Password sign-in and
password recovery remain available.

Enrollment is the only flow reached out of band, by an invitation link the operator sends;
`enrollment_flow` is deliberately unbound on the identification stage, because a sign-up link
would land on a flow that refuses anyone without a token.

Second factor is mandatory for every password sign-in. Upstream's MFA validation stage skips
users with no compatible device; the fleet requires it instead, accepting passkeys, email codes
and TOTP, with `configure` as the no-device action. A user with no method is therefore
enrolled on the way to a session rather than let through, and an account with two methods
chooses between them on one screen. The setup chooser offers two options, a passkey or a
password, and an authenticator app is added later under **Settings > MFA Devices**; TOTP
remains an accepted device class, so its holders sign in unchanged.

Passkey sign-in stays one step: a user-verified assertion from the username field skips the
password and the second factor, and upstream's policy for that is left unchanged.

Recovery is reachable without a credential from the sign-in page. The native emailed link
captures the recipient in its flow token. Before offering or saving a new password or creating
a session, a policy checks that recipient against the account's current address and refuses a
disabled account. Mailbox proof records ownership and establishes an email authenticator, so
the next password sign-in works without forcing TOTP setup. An address changed after link
issuance requires a new recovery link.

For an account that has never recorded email ownership, recovery removes its pre-verification
passkeys, TOTP and email devices and invalidates its password before completing the reset.
This prevents adoption of credentials someone attached to another person's address. Established
verified accounts retain their other devices until removed under **Settings > MFA Devices**.
Mailbox control remains the recovery root of trust.

Leaving enrollment after account creation grants no session. A usable passkey or password
returns through ordinary sign-in and its remaining gates. A reservation with no usable first
factor returns through recovery; account activity alone is not authentication.

Enrollment uses that same requirement before the session. The choice is a passkey or a
password, and the email step behind the password option is implicit: a passkey enrollee next
proves the email address, without setting a password, while the password branch sets up the
email factor — which proves the address — and then asks for the password, so no second code is
needed. The password prompt enforces the strength policy. There is no optional passkey checkbox. Passkeys require a discoverable credential and user verification (PIN or
biometric), with no platform-only attachment restriction: synced passkeys and compatible roaming
security keys are both allowed. No credential is created declaratively. Additional methods are
added later from the user menu under **Settings > MFA Devices > Enroll**.

### The verified-email gate

The login path challenges an unverified address with a code, and the proof that grants the
session is the confirmed device for the address the account currently carries. The gate calls the same verification policy as the standalone flow and re-evaluates it after
the code stage. `tests/assert-authentik-email-policy.py` exercises address ownership, device
reuse and administrative-status preservation.

An account without an address cannot pass the gate. Set and verify its address before relying
on it for sign-in, including the break-glass administrator.

`bash tests/check-authentik-enrollment.sh` exercises the shipped flows in an isolated official
image of the fleet's Authentik release. It checks actual session issuance, subsequent passkey,
email-OTP and TOTP sign-in, interrupted enrollment and recovery denial. Mail uses an in-memory
backend and the passkey is a virtual authenticator with valid signatures. Physical devices,
frontend presentation and real mail delivery remain operator acceptance; the test does not
claim to execute the Nix-built runtime.

## Account continuity

A federated identity is `(provider, subject)`, and the subject changes with the provider, so
no application carries an account across a swap by itself. What can carry it is the email
claim, matched by the application against its existing local user — which is why the claim
above is worth the machinery.

| Application | Continuity | Local sign-in |
| --- | --- | --- |
| Paperless | allauth email authentication with auto-connect (`VERIFIED_EMAIL`) | none — `PAPERLESS_DISABLE_REGULAR_LOGIN` under SSO; re-enable it for the window |
| Grafana | `oauth_allow_insecure_email_lookup` matches the existing user by email | none — `[auth] disable_login_form` with `[auth.basic] enabled = false`; the form returns only by deploy |
| Karakeep | `OAUTH_ALLOW_DANGEROUS_EMAIL_ACCOUNT_LINKING` | none — `disablePasswordAuth` |
| Homarr | `AUTH_OIDC_ENABLE_DANGEROUS_CREDENTIALS_LINKING`, enabled | only until the route publishes (`AUTH_PROVIDERS=credentials,oidc`) |
| Beszel | none | end users: none (`DISABLE_PASSWORD_AUTH`); PocketBase `superusers` keep theirs, which is the hub console |
| Actual | none — the account is the `preferred_username` claim | none — `allowedLoginMethods = [ "openid" ]` |
| Memos | none — local users and external identities are separate accounts | none for non-admins; the admin role keeps a password (upstream gates only the ordinary role) |
| Langfuse | `AUTH_CUSTOM_ALLOW_ACCOUNT_LINKING` | still offered until a login is confirmed, then `AUTH_DISABLE_USERNAME_PASSWORD` |
| Tududi, GeoPulse, BookOrbit | configured in their own settings | local admin |
| Inbox Zero | not an OIDC client — Google sign-in against an email allowlist | its own |

## Local administrator credential

Every OIDC application keeps one local administrator credential, and switching local sign-in
off hides that credential rather than removing it. Break-glass is re-enabling the local method
and deploying: it needs the host, not the identity provider, so a provider outage never takes
away the way back in. The credential belongs in the application's own service secret file,
next to its client secret.

| Application | Credential held | Break-glass |
| --- | --- | --- |
| Langfuse | `initial_admin/{email,password}` in SOPS, seeded on first start | re-enable password login |
| Paperless | `paperless/admin_pass` in SOPS, applied by `services.paperless.passwordFile` | re-enable regular login |
| Grafana | `grafana/admin_password`; the module defaults `services.grafana.secretFiles.admin` to it, and until the account exists the password lives in Grafana's own database | re-enable the login form |
| Karakeep | none; provider-created accounts carry no password | re-enable password auth, then set one |
| Actual | none; the account is the provider's `preferred_username` claim | re-enable the password method |
| Memos | admin-role password, set on the host | not needed — upstream gates the password by role |
| Beszel | PocketBase superuser password, set on the host | not needed — the gate is per collection |
| SparkyFitness | none in SOPS; the account is created through the application's own sign-up while password login is temporarily enabled | re-enable password login (`services.sparkyfitness.disablePasswordLogin = false`) and sign in as that account |

Only Langfuse, Paperless and Memos hold a credential that outlives an SSO-only deployment;
Grafana gains one as soon as its host binds the secret path, and Karakeep, Actual and
SparkyFitness have no supported seed for one, because the provider creates the first accounts
and never sets a password. SparkyFitness is the exception in how the account comes to exist: its
sign-up is open while password login is hidden, so the break-glass account is registered during
the same temporary override that makes it usable, and `adminEmail` keeps it administrative.
Where no credential exists the reset path is the redeploy itself, which is what the
applications reset in this change rely on — they carry no durable account state. Seeding the
rest is outstanding work, not a decision that they do without one.

Grafana's credential is service-scoped on purpose. `secrets/hosts/home-forge/oidc.yaml` also
encrypts to oci-melb-1, which needs the client secrets to provision providers and has no
reason to hold a credential that bypasses them, so the break-glass password lives in
`secrets/services/grafana.yaml`, encrypted to the owner and home-forge only:

```sh
just secrets bootstrap secrets/services/grafana.yaml
```

The Grafana aspect defaults `services.grafana.secretFiles.admin` to that file, so no host
record binds it; a host overrides the option only to point elsewhere. Grafana's
`admin_password` is applied from the file on the account's first creation.

Data-owning applications (Paperless, Memos, Langfuse) additionally need continuity or an
ownership decision — never a duplicate identity that quietly owns nothing.

Application-side state written by a login (Paperless social accounts, Homarr user rows)
changes with the provider, and reverting the route does not revert it.

## Application user provisioning

Authentik decides who may reach an application; the application decides whether an admitted
identity gets a local account. The fleet sets the second half explicitly wherever the upstream
default refuses, because that refusal surfaces as an app login error with no fleet-side record:

| Application | Provisioning |
| ----------- | ------------ |
| Actual | `userCreationMode = "login"` — upstream defaults to `manual`, which refuses an unknown identity silently |
| Paperless | `PAPERLESS_SOCIAL_AUTO_SIGNUP=true` — upstream defaults off, which stops the identity on allauth's signup form |
| Grafana | `allow_sign_up`, with role from the groups claim and a strict role that refuses non-admins |
| SparkyFitness | `SPARKY_FITNESS_OIDC_AUTO_REGISTER`, admin from the client's admin group |
| tududi | `OIDC_AUTO_PROVISION`; a provisioned account carries no password |
| GeoPulse | `GEOPULSE_AUTH_OIDC_REGISTRATION_ENABLED` |
| Memos | provisions on first SSO login while instance registration stays allowed |
| Homarr, Karakeep, Langfuse | create the account on first OIDC sign-in; roles stay application-owned |
| BookOrbit | its own settings hold an auto-provision toggle; the provider is configured there too |

## Dashboard visibility

An OIDC client's optional `showInDashboard` controls only its launcher card, projected through
Authentik's `meta_hide`. Cloudflare Access is hidden because it is the federation gate, not a
user-facing destination. Its provider, grant types and group access bindings remain unchanged.

Who sees a tile is otherwise the entry's `access`: those groups receive the card, so narrowing
Langfuse to `service-admins` both removes it from everyone else's dashboard and refuses them at
its OIDC login. A destination without single sign-on is a `links` entry — a launch-URL
application with no provider — which is how Search appears for `users`.

## Brand and login theme

The brand is keyed to the identity host's domain rather than replacing Authentik's default:
`branding_title`, theme base (dark), Dashboard layout, navbar display and the application-edit
feature. The horizontal logo, favicon and wallpaper use the public assets host; the dashboard
wallpaper is `theme.background` on Authentik's native fixed background layer, with the configured
tint included in that declaration.

`modules/identity/authentik/files/login-theme.css` owns the glass appearance: neutral frosted
surfaces, a rounded glass button and restrained blur. Text fields are transparent and underlined,
with brighter focus lines and red error feedback. Field text and light labels use Poiret One; the button and headings use Montserrat Alternates for legibility. Both load from Google Fonts' upstream TrueType files through commit-pinned jsDelivr
URLs, with system-font fallback.
No font is copied into this repository or the branding bucket.

The combined username/password form uses placeholders as visible prompts, while its labels
remain accessible. Its redundant heading is hidden; recovery and enrollment keep their titles.
Desktop uses a slim panel and generous vertical spacing. On narrow screens the panel fills the
viewport so the frost covers the whole page. Remember-me is styled as a toggle in place; moving
it would need a rebuild of Authentik's frontend. Typing and caret movement remain native; only
focus-line and placeholder transitions animate, and they respect reduced-motion preferences.
The stylesheet adapts styling from VULGA01's
MIT-licensed Glassmorphism theme at revision `0003939` and retains its notice, but does not
include or fetch that stylesheet. `_blueprint/theme.nix` reads the file and supplies the policy's wallpaper
and tint tokens.

Authentik retains layout, breakpoints, form state and menu behaviour. Flow pages tint the image
on Authentik's existing `body::before`; the dashboard uses its native `theme.background` layer
without CSS resets. Component variables supply colours and spacing; selectors handle surface
blur, branding and the dashboard header's stacking context. The admin interface is not restyled.

An Authentik upgrade needs browser checks of login, recovery, enrollment and the dashboard at
mobile and desktop widths, including keyboard focus, logo sizing and clicks on the open profile
menu. A successful blueprint import does not establish visual acceptance.
