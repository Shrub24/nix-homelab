# Mail

Every service sends through the fleet's relay account, and each service sends from its
own address on `shrublab.xyz`.

## Senders

| Service | From |
| --- | --- |
| Authentik | `auth@shrublab.xyz` |
| Vaultwarden | `vault@shrublab.xyz` |
| Latitude | `latitude@shrublab.xyz` |

Every address derives from the `domain` value in `policy/globals.nix`, which is the only place the suffix is written; a module composes `vault@${domain}` rather than repeating it. Each sender belongs to its owning aspect, not to a host's configuration.

A new service takes its own local part. The address is part of that service's
user-facing identity — a person can tell at a glance which system wrote to them, and can
filter or block one stream without touching another.

A single shared sender (`no-reply@shrublab.xyz` with a `Reply-To` into a monitored
mailbox) was rejected: it is fewer literals to keep, but the saving is not worth losing
the per-service identity, and the deliverability argument does not support it anyway —
reputation attaches to the domain and the relay's addresses, not to the local part.

What the addresses do **not** provide is isolation. Every sender shares one domain and one
relay, so a blocklist or a reputation hit takes them all. Real isolation needs either a
separate sending subdomain or a separate relay account; neither is warranted today, and
the revisit trigger is a service whose mail volume or complaint rate starts affecting
delivery of the others.

## Relay

One account, reused rather than duplicated: `smtp.resend.com` on port 587 with STARTTLS,
credential in `secrets/applications/admin.yaml` (see
`docs/runbooks/authentik-secrets.md` for the key names). Providers that need it take the
same account; the addresses differ, the credential does not.

That account is also the delivery path for the confirmation links enrollment depends on, so
a broken relay blocks onboarding rather than just notifications.

`shrublab.xyz` must stay verified at the relay with DKIM so that any local part aligns;
DMARC should publish at least `p=quarantine`. Bounces go back to the relay, not to a
mailbox, so failed delivery is visible in its events rather than in an inbox.
