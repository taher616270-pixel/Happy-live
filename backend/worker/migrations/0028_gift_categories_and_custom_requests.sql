-- Gift categories, event schedules, country targeting and custom gift requests.
ALTER TABLE gift_catalog ADD COLUMN category TEXT NOT NULL DEFAULT 'trending' CHECK (category IN ('trending','event','country','lucky','custom'));
ALTER TABLE gift_catalog ADD COLUMN country_name TEXT;
ALTER TABLE gift_catalog ADD COLUMN starts_at TEXT;
ALTER TABLE gift_catalog ADD COLUMN ends_at TEXT;
CREATE INDEX IF NOT EXISTS idx_gift_catalog_category_active ON gift_catalog(category,is_active,country_name,sort_order);

CREATE TABLE IF NOT EXISTS gift_custom_requests (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  requested_name TEXT NOT NULL CHECK(length(requested_name) BETWEEN 2 AND 60),
  details TEXT NOT NULL DEFAULT '' CHECK(length(details)<=300),
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected')),
  linked_gift_id TEXT REFERENCES gift_catalog(id) ON DELETE SET NULL,
  reviewed_by_admin_id TEXT,
  review_note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_gift_custom_requests_status_created ON gift_custom_requests(status,created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_gift_custom_requests_one_pending_per_user ON gift_custom_requests(user_id) WHERE status='pending';
