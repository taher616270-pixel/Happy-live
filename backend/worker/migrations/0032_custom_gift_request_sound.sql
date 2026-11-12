-- Keep optional MP3 audio submitted by users with custom gift requests.
ALTER TABLE gift_custom_requests ADD COLUMN sound_url TEXT;
ALTER TABLE gift_custom_requests ADD COLUMN sound_file_id TEXT;
