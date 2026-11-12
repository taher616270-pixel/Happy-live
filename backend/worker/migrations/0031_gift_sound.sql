-- Store a separate audio asset for each animated gift.
-- The audio remains optional so existing gifts keep working unchanged.
ALTER TABLE gift_catalog ADD COLUMN sound_url TEXT;
