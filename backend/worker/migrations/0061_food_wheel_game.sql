-- Register the independent Food Wheel game. Existing games are intentionally untouched.
INSERT OR IGNORE INTO game_registry
  (id, name, game_url, icon_url, description, category, enabled, sort_order, created_by_admin_id, created_at, updated_at)
VALUES
  ('4bcb9b74-3c87-4d9e-9f26-2b61c9a5f841', 'عجلة الأطعمة', 'https://happy-live.pages.dev', NULL,
   'عجلة الأطعمة داخل غرف Happy Live مع تسوية رهانات من الخادم.', 'ألعاب', 1, 30, NULL,
   strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));

INSERT INTO game_registry_lifecycle (game_id, status, updated_at)
VALUES ('4bcb9b74-3c87-4d9e-9f26-2b61c9a5f841', 'active', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
ON CONFLICT(game_id) DO UPDATE SET status = 'active', updated_at = excluded.updated_at;
