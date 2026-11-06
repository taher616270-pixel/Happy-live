-- Replies attached to existing top-level post comments.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS post_comment_replies (
  id TEXT PRIMARY KEY,
  comment_id TEXT NOT NULL REFERENCES post_comments(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content TEXT NOT NULL CHECK (length(content) BETWEEN 1 AND 500),
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_post_comment_replies_comment
  ON post_comment_replies(comment_id, created_at ASC);
