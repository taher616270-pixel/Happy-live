-- Application-wide gift banner threshold. A zero threshold disables banners until the owner configures it.
CREATE TABLE IF NOT EXISTS gift_banner_settings (
  id TEXT PRIMARY KEY CHECK (id = 'current'),
  enabled INTEGER NOT NULL DEFAULT 0 CHECK (enabled IN (0, 1)),
  minimum_coins INTEGER NOT NULL DEFAULT 0 CHECK (minimum_coins >= 0),
  updated_by_admin_id TEXT,
  updated_at TEXT NOT NULL
);

INSERT OR IGNORE INTO gift_banner_settings (id, enabled, minimum_coins, updated_at)
VALUES ('current', 0, 0, CURRENT_TIMESTAMP);
