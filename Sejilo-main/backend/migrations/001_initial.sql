CREATE TABLE IF NOT EXISTS schema_migrations (
  version text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE devices (
  device_id text PRIMARY KEY,
  user_id text NULL,
  platform text NOT NULL CHECK (platform IN ('android', 'windows', 'linux', 'macos', 'ios')),
  public_key bytea NOT NULL UNIQUE CHECK (octet_length(public_key) = 32),
  protocol_versions smallint[] NOT NULL,
  capabilities text[] NOT NULL DEFAULT '{}',
  disabled_at timestamptz NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_authenticated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE device_public_keys (
  device_id text NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  key_version integer NOT NULL CHECK (key_version > 0),
  public_key bytea NOT NULL CHECK (octet_length(public_key) = 32),
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz NULL,
  PRIMARY KEY (device_id, key_version),
  UNIQUE (public_key)
);

CREATE TABLE device_sessions (
  session_id uuid PRIMARY KEY,
  device_id text NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  token_hash bytea NOT NULL UNIQUE CHECK (octet_length(token_hash) = 32),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz NULL,
  CHECK (expires_at > created_at)
);
CREATE INDEX device_sessions_active_token_idx
  ON device_sessions (token_hash, expires_at) WHERE revoked_at IS NULL;
CREATE INDEX device_sessions_device_idx ON device_sessions (device_id, expires_at DESC);

CREATE TABLE conversations (
  conversation_id text PRIMARY KEY,
  kind text NOT NULL CHECK (kind IN ('direct', 'group')),
  created_by_device_id text NOT NULL REFERENCES devices(device_id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE conversation_members (
  conversation_id text NOT NULL REFERENCES conversations(conversation_id) ON DELETE CASCADE,
  device_id text NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'member' CHECK (role IN ('member', 'admin', 'owner')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  left_at timestamptz NULL,
  PRIMARY KEY (conversation_id, device_id)
);

CREATE TABLE groups (
  group_id text PRIMARY KEY,
  conversation_id text NOT NULL UNIQUE REFERENCES conversations(conversation_id) ON DELETE CASCADE,
  encrypted_metadata bytea NOT NULL,
  key_epoch integer NOT NULL DEFAULT 1 CHECK (key_epoch > 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE group_members (
  group_id text NOT NULL REFERENCES groups(group_id) ON DELETE CASCADE,
  device_id text NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'member' CHECK (role IN ('member', 'admin', 'owner')),
  key_epoch integer NOT NULL CHECK (key_epoch > 0),
  encrypted_key_material bytea NOT NULL,
  joined_at timestamptz NOT NULL DEFAULT now(),
  removed_at timestamptz NULL,
  PRIMARY KEY (group_id, device_id)
);

CREATE TABLE encrypted_messages (
  message_id text PRIMARY KEY,
  packet_id text NOT NULL UNIQUE,
  sender_device_id text NOT NULL REFERENCES devices(device_id),
  recipient_device_id text NULL REFERENCES devices(device_id),
  group_id text NULL REFERENCES groups(group_id),
  protocol_version smallint NOT NULL CHECK (protocol_version BETWEEN 1 AND 255),
  packet_type text NOT NULL CHECK (packet_type IN ('message', 'receipt', 'group_message', 'gateway')),
  ttl smallint NOT NULL CHECK (ttl BETWEEN 0 AND 32),
  hop_count smallint NOT NULL CHECK (hop_count BETWEEN 0 AND ttl),
  payload_type text NOT NULL CHECK (payload_type IN ('ciphertext', 'encrypted_attachment_manifest')),
  encrypted_payload bytea NULL,
  payload_sha256 bytea NOT NULL CHECK (octet_length(payload_sha256) = 32),
  payload_bytes integer NOT NULL CHECK (payload_bytes > 0),
  origin_created_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  server_accepted_at timestamptz NOT NULL DEFAULT now(),
  payload_erased_at timestamptz NULL,
  CHECK ((recipient_device_id IS NULL) <> (group_id IS NULL)),
  CHECK (expires_at > origin_created_at),
  CHECK ((encrypted_payload IS NULL) = (payload_erased_at IS NOT NULL))
);
CREATE INDEX encrypted_messages_sender_idx
  ON encrypted_messages (sender_device_id, server_accepted_at DESC);
CREATE INDEX encrypted_messages_expiry_idx
  ON encrypted_messages (expires_at) WHERE encrypted_payload IS NOT NULL;

CREATE TABLE message_recipients (
  message_id text NOT NULL REFERENCES encrypted_messages(message_id) ON DELETE CASCADE,
  recipient_device_id text NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  state text NOT NULL DEFAULT 'server_accepted'
    CHECK (state IN ('server_accepted', 'delivered_to_device', 'read', 'expired', 'failed')),
  delivery_attempts integer NOT NULL DEFAULT 0 CHECK (delivery_attempts >= 0),
  last_attempt_at timestamptz NULL,
  delivered_at timestamptz NULL,
  read_at timestamptz NULL,
  PRIMARY KEY (message_id, recipient_device_id)
);
CREATE INDEX message_recipients_pending_idx
  ON message_recipients (recipient_device_id, state, message_id)
  WHERE state = 'server_accepted';

CREATE TABLE delivery_receipts (
  receipt_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  message_id text NOT NULL REFERENCES encrypted_messages(message_id) ON DELETE CASCADE,
  recipient_device_id text NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  state text NOT NULL CHECK (state IN ('delivered_to_device', 'read')),
  acknowledged_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (message_id, recipient_device_id, state)
);
CREATE INDEX delivery_receipts_sender_sync_idx
  ON delivery_receipts (message_id, acknowledged_at);

CREATE TABLE attachment_metadata (
  attachment_id text PRIMARY KEY,
  message_id text NOT NULL REFERENCES encrypted_messages(message_id) ON DELETE CASCADE,
  owner_device_id text NOT NULL REFERENCES devices(device_id),
  storage_object_id text NOT NULL UNIQUE,
  ciphertext_bytes bigint NOT NULL CHECK (ciphertext_bytes BETWEEN 1 AND 1073741824),
  ciphertext_sha256 bytea NOT NULL CHECK (octet_length(ciphertext_sha256) = 32),
  encrypted_metadata bytea NOT NULL,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX attachment_metadata_expiry_idx ON attachment_metadata (expires_at);

CREATE TABLE trusted_devices (
  owner_device_id text NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  trusted_device_id text NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  verified_fingerprint text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (owner_device_id, trusted_device_id),
  CHECK (owner_device_id <> trusted_device_id)
);

CREATE TABLE blocked_peers (
  owner_device_id text NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  blocked_device_id text NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (owner_device_id, blocked_device_id),
  CHECK (owner_device_id <> blocked_device_id)
);

CREATE TABLE gateway_preferences (
  device_id text PRIMARY KEY REFERENCES devices(device_id) ON DELETE CASCADE,
  enabled boolean NOT NULL DEFAULT false,
  trusted_only boolean NOT NULL DEFAULT true,
  allow_metered boolean NOT NULL DEFAULT false,
  charging_only boolean NOT NULL DEFAULT true,
  daily_byte_limit bigint NOT NULL DEFAULT 0 CHECK (daily_byte_limit >= 0),
  temporary_storage_limit_bytes bigint NOT NULL DEFAULT 0 CHECK (temporary_storage_limit_bytes >= 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE abuse_events (
  event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  device_id text NULL REFERENCES devices(device_id) ON DELETE SET NULL,
  ip_hash bytea NULL,
  category text NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'
);
CREATE INDEX abuse_events_device_time_idx ON abuse_events (device_id, occurred_at DESC);
CREATE INDEX abuse_events_category_time_idx ON abuse_events (category, occurred_at DESC);
