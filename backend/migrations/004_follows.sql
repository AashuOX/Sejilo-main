CREATE TABLE follows (
  follower_user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  following_user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (follower_user_id, following_user_id),
  CHECK (follower_user_id <> following_user_id)
);
CREATE INDEX follows_following_idx ON follows(following_user_id, created_at DESC);
