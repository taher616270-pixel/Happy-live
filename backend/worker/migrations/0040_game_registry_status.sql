ALTER TABLE game_registry
ADD COLUMN status TEXT NOT NULL DEFAULT 'disabled'
CHECK(status IN ('development', 'disabled', 'active'));

UPDATE game_registry
SET status = CASE WHEN enabled = 1 THEN 'active' ELSE 'disabled' END;
