-- Store room profile reports in D1 for review inside the independent admin dashboard.
CREATE TABLE IF NOT EXISTS room_profile_reports (
  id TEXT PRIMARY KEY,
  room_code TEXT NOT NULL,
  room_name TEXT NOT NULL,
  reporter_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  targets_json TEXT NOT NULL,
  violation TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'dismissed')),
  created_at TEXT NOT NULL,
  reviewed_at TEXT,
  reviewed_by TEXT REFERENCES admin_accounts(id)
);
CREATE INDEX IF NOT EXISTS idx_room_profile_reports_status_created
  ON room_profile_reports(status, created_at DESC);
