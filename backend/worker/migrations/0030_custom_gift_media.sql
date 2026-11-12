-- Add uploaded animation metadata to custom gift requests.
-- Files are uploaded to ImageKit; only the delivery metadata is stored in D1.
ALTER TABLE gift_custom_requests ADD COLUMN media_url TEXT;
ALTER TABLE gift_custom_requests ADD COLUMN media_type TEXT
  CHECK (media_type IS NULL OR media_type IN ('gif', 'svga'));
ALTER TABLE gift_custom_requests ADD COLUMN media_duration_ms INTEGER
  CHECK (media_duration_ms IS NULL OR (media_duration_ms BETWEEN 1 AND 5000));
ALTER TABLE gift_custom_requests ADD COLUMN media_file_id TEXT;
CREATE INDEX IF NOT EXISTS idx_gift_custom_requests_media_file
  ON gift_custom_requests(media_file_id);
