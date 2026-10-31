# Authentik blueprint acceptance

See [Identity](../identity.md#deployment-gate) for ownership and validation boundaries.

## Before deployment

1. Run `git add -A` after editing tracked or new sources.
2. Build the provider's `services.authentik.settings.blueprints_dir` with native build tools or its configured architecture builder.
3. Run `just checks all` on the settled tree.
4. Obtain deployment approval and retain an independent SSH session.

## After deployment

1. On the provider host, check:

   ```sh
   systemctl status authentik-blueprint-validate.service --no-pager
   journalctl -u authentik-blueprint-validate.service --no-pager -n 20
   ```

2. Record that the unit exited successfully for the current generation.
3. Sign in with password and passkey, then open an OIDC application. Record browser acceptance separately.

## Rejection or timeout

1. Retain the failed deployment result and the gate's failure category.
2. Check `authentik-migrate`, `authentik-worker` and `authentik` unit status.
3. In Authentik's administrator interface, inspect the fleet blueprint instance and its task result. Do not paste resolved credentials or complete serializer payloads into reports.
4. Correct the source document or restore the previously accepted source, then rebuild and redeploy.
5. To recheck without a generation change, run:

   ```sh
   sudo systemctl restart authentik-blueprint-validate.service
   ```

6. If object state needs restoration, use the identity backup/restore procedure. Verify the gate and browser login again after recovery.
