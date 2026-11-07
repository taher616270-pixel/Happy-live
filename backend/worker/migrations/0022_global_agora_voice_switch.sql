-- Persist the platform-wide Agora voice service state.
CREATE TABLE IF NOT EXISTS platform_settings (
  setting_key TEXT PRIMARY KEY,
  setting_value TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

INSERT INTO platform_settings (setting_key, setting_value, updated_at)
VALUES ('agora_voice_enabled', 'true', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
ON CONFLICT(setting_key) DO NOTHING;
