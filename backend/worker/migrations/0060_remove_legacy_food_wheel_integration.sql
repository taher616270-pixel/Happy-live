-- Decommission the retired external Food Wheel platform integration.
-- Preserve historical wallet callback rows as an immutable archive.
ALTER TABLE platform_game_callback_orders RENAME TO legacy_platform_game_callback_orders_archive;
DROP INDEX IF EXISTS idx_platform_game_orders_user_created;

DELETE FROM platform_settings
WHERE setting_key IN (
  'happy_food_wheel_app_id',
  'happy_food_wheel_token_hash',
  'happy_food_wheel_token_prefix',
  'happy_food_wheel_created_at'
);
