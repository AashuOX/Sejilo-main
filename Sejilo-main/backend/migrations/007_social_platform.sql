CREATE TABLE IF NOT EXISTS post_saves (
  user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  post_id uuid NOT NULL REFERENCES posts(post_id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(user_id, post_id)
);
CREATE INDEX IF NOT EXISTS post_saves_user_idx ON post_saves(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS notifications (
  notification_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  actor_user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  type text NOT NULL CHECK (type IN ('like', 'comment', 'follow', 'mention')),
  post_id uuid NULL REFERENCES posts(post_id) ON DELETE CASCADE,
  comment_id uuid NULL REFERENCES post_comments(comment_id) ON DELETE CASCADE,
  is_read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS notifications_user_idx ON notifications(user_id, created_at DESC);
