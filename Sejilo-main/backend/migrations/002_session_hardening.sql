ALTER TABLE device_sessions
  ADD COLUMN IF NOT EXISTS refresh_token_hash bytea NULL,
  ADD COLUMN IF NOT EXISTS refresh_expires_at timestamptz NULL;

ALTER TABLE device_sessions
  DROP CONSTRAINT IF EXISTS device_sessions_refresh_shape;
ALTER TABLE device_sessions
  ADD CONSTRAINT device_sessions_refresh_shape CHECK (
    (refresh_token_hash IS NULL AND refresh_expires_at IS NULL) OR
    (octet_length(refresh_token_hash) = 32 AND refresh_expires_at > expires_at)
  );

CREATE UNIQUE INDEX IF NOT EXISTS device_sessions_active_refresh_idx
  ON device_sessions (refresh_token_hash)
  WHERE revoked_at IS NULL AND refresh_token_hash IS NOT NULL;
