-- Ensure the per-user comment cooldown table exists in production.
-- Earlier deployments applied the nested-reply column without applying this table.
CREATE TABLE IF NOT EXISTS post_comment_rate_limits (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  last_comment_at TEXT NOT NULL
);
