-- Social post privacy, hidden users, and reports.
ALTER TABLE posts ADD COLUMN visibility TEXT NOT NULL DEFAULT 'public' CHECK (visibility IN ('public', 'followers', 'private'));
CREATE TABLE IF NOT EXISTS user_hidden_users (user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, hidden_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, created_at TEXT NOT NULL, PRIMARY KEY (user_id, hidden_user_id), CHECK (user_id <> hidden_user_id));
CREATE INDEX IF NOT EXISTS idx_user_hidden_users_hidden ON user_hidden_users(hidden_user_id);
CREATE TABLE IF NOT EXISTS post_reports (id TEXT PRIMARY KEY, post_id TEXT NOT NULL REFERENCES posts(id) ON DELETE CASCADE, reporter_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, reported_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, reason TEXT NOT NULL DEFAULT 'general', created_at TEXT NOT NULL, UNIQUE (post_id, reporter_id));
CREATE INDEX IF NOT EXISTS idx_post_reports_created ON post_reports(created_at DESC);
