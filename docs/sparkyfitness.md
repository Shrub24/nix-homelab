# SparkyFitness

A fitness and nutrition application at `https://fit.shrublab.xyz`, placed on `oci-melb-1`. The aspect is `sparkyfitness` (`modules/apps/sparkyfitness.nix`).

## Runtime

Two upstream release images on a dedicated Podman network. `sparkyfitness-server` is the API; it is bridged, publishes no port, and reaches the cluster through the service address. `sparkyfitness-frontend` is the React application behind nginx, published on loopback at the port `policy/web-services.nix` declares, so the Caddy edge forwards the whole site to it.

The frontend image's nginx is part of the deployment: it serves the assets and proxies `/api`, `/uploads`, `/health-data`, `/mcp` and the OIDC discovery paths to the backend. The fleet owns ingress, not application serving.

## Data

| What | Where | Recovery |
| --- | --- | --- |
| Records | PostgreSQL database `sparkyfitness` on the host's cluster | the substrate's `pg_dumpall` export |
| Uploaded files | `/srv/data/sparkyfitness/uploads` | captured live by restic |
| Application-written dumps | `/srv/data/sparkyfitness/backup` | not captured — the substrate export already covers the database |
| Encryption key | `app/encryption_key` in the service secret | required for encrypted integration credentials |

The database and the uploaded files are captured by different mechanisms at different moments, so a backup represents the files at capture time and the database at dump time. A record added between the two can therefore be missing its upload. Uploads that are written and acknowledged through the same request are consistent; in-flight uploads during a backup window are not.

## Sign-in

Authentik is the sign-in path. The client is `sparkyfitness` in `policy/identity.nix`; its callback is `/api/auth/sso/callback/authentik` on the public origin, and the provider slug comes from `policy.identity.provider`. OIDC follows the route's `access.oidc` flag, and the host binds the client secret from the same `secrets/hosts/oci-melb-1/oidc.yaml` the provider reads.

Administrator access follows the provider's `groups` claim against `services.sparkyfitness.adminGroup`, which defaults to the first admin group the client admits — the same group the provider binds the `sparkyfitness-admin` entitlement to, so the app's own check and the provider's role cannot disagree. `adminEmail` is the additional break-glass override.

The application's own email/password login is hidden (`disablePasswordLogin` defaults true) and its local passkey login is off, because interactive MFA belongs to the identity provider. Sign-up stays open, deliberately: upstream applies the sign-up blockade to SSO account creation as well, so closing it would stop approved users from arriving through the provider. A password account created while sign-up is open cannot sign in while password login is hidden.

## Operations

`docs/runbooks/sparkyfitness.md` covers secret preparation, deploy, acceptance, break-glass and restore. The identity host's break-glass credential is recorded in `docs/identity.md`.
