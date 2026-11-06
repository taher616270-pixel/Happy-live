-- Add the parent pointer required by nested comment replies.
-- Existing replies remain top-level because the new column defaults to NULL.
ALTER TABLE post_comment_replies ADD COLUMN parent_reply_id TEXT REFERENCES post_comment_replies(id) ON DELETE CASCADE;
