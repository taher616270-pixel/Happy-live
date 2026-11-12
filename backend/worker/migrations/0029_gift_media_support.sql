-- Store the media source and renderer type for each gift.
-- Existing gifts remain emoji-only and continue to work unchanged.
ALTER TABLE gift_catalog ADD COLUMN media_url TEXT;
ALTER TABLE gift_catalog ADD COLUMN media_type TEXT NOT NULL DEFAULT 'emoji'
  CHECK (media_type IN ('emoji', 'svga', 'apng', 'webp'));
