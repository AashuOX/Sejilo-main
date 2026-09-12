ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS google_id text NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_new_user boolean NOT NULL DEFAULT false;

CREATE UNIQUE INDEX IF NOT EXISTS users_google_id_unique_idx ON users(google_id) WHERE google_id IS NOT NULL;
