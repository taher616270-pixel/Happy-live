-- Temporary room kick state; distinct from a permanent room ban.
ALTER TABLE room_user_controls ADD COLUMN kicked_until TEXT;
