# Authentik secrets

The provider stays inert until `secrets/identity/authentik.yaml` exists: selecting the
`authentik-identity` aspect is the only enablement, and the module gates its runtime on
that file. Creating the file is the operator's staging step, and `.sops.yaml` scopes it to
the identity host alone.

## Required keys

```yaml
authentik:
  # Signs sessions and encrypted fields. Losing it invalidates every session and
  # any field encrypted with it; it is part of the recovery set.
  secret_key: <64+ characters>
  # The role's password; the same value is provisioned into PostgreSQL and read by
  # the runtime, so it has one source.
  postgres_password: <random>
  # First administrator, created on first start. Rotate it after the account exists.
  bootstrap_password: <random>
  # API token for the same bootstrap administrator, used by operator tooling.
  bootstrap_token: <random>
  # The mail relay account enrollment and recovery send through.
  smtp_username: <relay username>
  smtp_password: <relay password>
```

Client credentials are not in this file. Each client keeps its existing encrypted
credential (`secrets/hosts/<host>/oidc.yaml`, `secrets/services/<name>.yaml`,
`secrets/opentofu/oidc.yaml`) and the provider reads the same key from that file, so no
secret exists twice and a rotation moves the application and the provider together.

## Mail delivery

Enrollment confirmation and password recovery both send mail through the relay account
held in this file as `authentik/smtp_username` and `authentik/smtp_password`. Host, port and sender are fixed in `modules/identity/authentik/server.nix`
(`smtp.resend.com:587`, STARTTLS, `admin@shrublab.xyz`), so a mail change is one edit
there.

Enrollment cannot complete until delivery works: send a test from the Authentik admin
interface (System > Email) before accepting invitations.

## Applying

Encrypt with the repository's usual SOPS workflow, then deploy `oci-melb-1`. Never edit or
decrypt the file as part of a code change; that step belongs to the operator.

## Rotation

The secret key is not a rotatable credential in place: changing it invalidates sessions and
anything encrypted with it. Rotate client secrets in Authentik and the application together.
