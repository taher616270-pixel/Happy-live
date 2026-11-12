-- Gift catalogue categories, country targeting, scheduled events, and custom gift requests.
PRAGMA foreign_keys = ON;

ALTER TABLE gift_catalog ADD COLUMN category TEXT NOT NULL DEFAULT 'trending'
  CHECK (category IN ('event', 'trending', 'country', 'lucky', 'custom'));
ALTER TABLE gift_catalog ADD COLUMN country_code TEXT;
ALTER TABLE gift_catalog ADD COLUMN starts_at TEXT;
ALTER TABLE gift_catalog ADD COLUMN ends_at TEXT;
CREATE INDEX IF NOT EXISTS idx_gift_catalog_category_country_active
  ON gift_catalog(category, country_code, is_active, sort_order, created_at);

CREATE TABLE IF NOT EXISTS gift_custom_requests (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  requested_name TEXT NOT NULL CHECK (length(requested_name) BETWEEN 2 AND 80),
  description TEXT NOT NULL DEFAULT '' CHECK (length(description) <= 500),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  admin_note TEXT NOT NULL DEFAULT '' CHECK (length(admin_note) <= 500),
  approved_gift_id TEXT REFERENCES gift_catalog(id) ON DELETE SET NULL,
  reviewed_by_admin_id TEXT,
  reviewed_at TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_gift_custom_requests_status_created
  ON gift_custom_requests(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_gift_custom_requests_user_created
  ON gift_custom_requests(user_id, created_at DESC);
