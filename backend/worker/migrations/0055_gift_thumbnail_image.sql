-- Optional static artwork used only in the room gift picker; animated delivery media remains separate.
ALTER TABLE gift_catalog ADD COLUMN thumbnail_url TEXT;
