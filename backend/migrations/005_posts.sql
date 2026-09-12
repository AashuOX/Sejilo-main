CREATE TABLE posts (
  post_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  media_bytes bytea NOT NULL CHECK (octet_length(media_bytes) BETWEEN 1 AND 5242880),
  media_mime_type text NOT NULL CHECK (media_mime_type IN ('image/png','image/jpeg','image/webp')),
  caption text NOT NULL DEFAULT '' CHECK (char_length(caption) <= 2200),
  created_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz NULL
);
CREATE INDEX posts_visible_created_idx ON posts(created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX posts_user_created_idx ON posts(user_id,created_at DESC) WHERE deleted_at IS NULL;
CREATE TABLE post_likes (user_id uuid REFERENCES users(user_id) ON DELETE CASCADE, post_id uuid REFERENCES posts(post_id) ON DELETE CASCADE, created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(user_id,post_id));
CREATE TABLE post_comments (comment_id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, post_id uuid NOT NULL REFERENCES posts(post_id) ON DELETE CASCADE, text text NOT NULL CHECK(char_length(text) BETWEEN 1 AND 1000), created_at timestamptz NOT NULL DEFAULT now(), deleted_at timestamptz NULL);
CREATE INDEX post_comments_post_idx ON post_comments(post_id,created_at) WHERE deleted_at IS NULL;
