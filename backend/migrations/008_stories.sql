CREATE TABLE IF NOT EXISTS stories (
  story_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  type text NOT NULL CHECK (type IN ('image', 'text')),
  media jsonb NULL,
  text_content text NULL,
  background_style text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '24 hours')
);

CREATE INDEX IF NOT EXISTS stories_user_expires_idx ON stories(user_id, expires_at DESC);
CREATE INDEX IF NOT EXISTS stories_active_idx ON stories(expires_at DESC, created_at DESC);

CREATE TABLE IF NOT EXISTS story_views (
  story_id uuid NOT NULL REFERENCES stories(story_id) ON DELETE CASCADE,
  viewer_user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  viewed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(story_id, viewer_user_id)
);

CREATE INDEX IF NOT EXISTS story_views_story_idx ON story_views(story_id, viewed_at DESC);
