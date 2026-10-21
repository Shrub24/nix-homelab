-- PKCE (RFC 7636): the verifier whose S256 challenge the login sent to the provider.
-- Repeatable and idempotent: upstream owns every V36.x number, and 2.0 reuses the
-- 36.53.0 this patch first occupied, so a versioned file here collides. Repeatable
-- migrations run after the versioned stream and re-run only when this file changes.
ALTER TABLE oidc_session_states ADD COLUMN IF NOT EXISTS code_verifier VARCHAR(128);
