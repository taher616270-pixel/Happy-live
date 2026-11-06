-- Allow replies to replies and enforce a per-user 30-second top-level comment cooldown.
ALTER TABLE post_comment_replies ADD COLUMN parent_reply_id TEXT
  REFERENCES post_comment_replies(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_post_comment_replies_parent
  ON post_comment_replies(parent_reply_id, created_at ASC);

CREATE TABLE IF NOT EXISTS post_comment_rate_limits (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  last_comment_at TEXT NOT NULL
);
