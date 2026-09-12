CREATE TABLE users (
  user_id uuid PRIMARY KEY,
  email text NOT NULL,
  password_hash text NOT NULL,
  username text NOT NULL,
  display_name text NOT NULL,
  bio text NOT NULL DEFAULT '',
  avatar_bytes bytea NULL,
  avatar_mime_type text NULL,
  email_verified_at timestamptz NULL,
  disabled_at timestamptz NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (email = lower(email)),
  CHECK (username = lower(username)),
  CHECK (char_length(username) BETWEEN 3 AND 32),
  CHECK (char_length(display_name) BETWEEN 1 AND 80),
  CHECK (char_length(bio) <= 500),
  CHECK ((avatar_bytes IS NULL) = (avatar_mime_type IS NULL)),
  CHECK (avatar_bytes IS NULL OR octet_length(avatar_bytes) <= 262144),
  CHECK (avatar_mime_type IS NULL OR avatar_mime_type IN ('image/png', 'image/jpeg', 'image/webp'))
);
CREATE UNIQUE INDEX users_email_unique_idx ON users(email);
CREATE UNIQUE INDEX users_username_unique_idx ON users(username);

CREATE TABLE user_sessions (
  session_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  token_hash bytea NOT NULL UNIQUE CHECK (octet_length(token_hash) = 32),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz NULL,
  CHECK (expires_at > created_at)
);
CREATE INDEX user_sessions_active_token_idx ON user_sessions(token_hash, expires_at)
  WHERE revoked_at IS NULL;

CREATE TABLE password_reset_tokens (
  reset_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  token_hash bytea NOT NULL UNIQUE CHECK (octet_length(token_hash) = 32),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  used_at timestamptz NULL,
  CHECK (expires_at > created_at)
);
CREATE INDEX password_reset_tokens_active_idx ON password_reset_tokens(token_hash, expires_at)
  WHERE used_at IS NULL;
