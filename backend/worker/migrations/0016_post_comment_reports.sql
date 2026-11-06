-- Store post-comment reports durably for the admin moderation queue.
CREATE TABLE IF NOT EXISTS post_comment_reports (
  id TEXT PRIMARY KEY,
  post_id TEXT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  comment_id TEXT NOT NULL,
  reporter_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reported_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reason TEXT NOT NULL DEFAULT 'general',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'dismissed', 'actioned')),
  created_at TEXT NOT NULL,
  reviewed_at TEXT,
  reviewed_by TEXT REFERENCES users(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_post_comment_reports_reporter
  ON post_comment_reports(comment_id, reporter_id);
CREATE INDEX IF NOT EXISTS idx_post_comment_reports_status_created
  ON post_comment_reports(status, created_at DESC);
