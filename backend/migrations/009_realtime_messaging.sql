CREATE TABLE IF NOT EXISTS user_conversations (
  conversation_id uuid PRIMARY KEY,
  kind text NOT NULL CHECK (kind IN ('direct', 'group')),
  title text NULL,
  created_by_user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS user_conversations_updated_idx ON user_conversations(updated_at DESC);

CREATE TABLE IF NOT EXISTS user_conversation_members (
  conversation_id uuid NOT NULL REFERENCES user_conversations(conversation_id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'member' CHECK (role IN ('member', 'admin', 'owner')),
  last_read_at timestamptz NOT NULL DEFAULT now(),
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_id, user_id)
);

CREATE INDEX IF NOT EXISTS user_conversation_members_user_idx ON user_conversation_members(user_id, last_read_at DESC);

CREATE TABLE IF NOT EXISTS direct_messages (
  message_id uuid PRIMARY KEY,
  conversation_id uuid NOT NULL REFERENCES user_conversations(conversation_id) ON DELETE CASCADE,
  sender_user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  text text NULL,
  media jsonb NULL,
  reply_to_message_id uuid NULL REFERENCES direct_messages(message_id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'sent' CHECK (status IN ('sending', 'sent', 'delivered', 'read')),
  created_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz NULL
);

CREATE INDEX IF NOT EXISTS direct_messages_conv_created_idx ON direct_messages(conversation_id, created_at ASC);
CREATE INDEX IF NOT EXISTS direct_messages_sender_idx ON direct_messages(sender_user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS message_reactions (
  message_id uuid NOT NULL REFERENCES direct_messages(message_id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  emoji text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id)
);
