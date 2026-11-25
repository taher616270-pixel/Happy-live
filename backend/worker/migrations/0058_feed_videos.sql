-- Short-video feed metadata and engagement.
PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS feed_videos (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  video_url TEXT NOT NULL,
  caption TEXT NOT NULL DEFAULT '',
  sound TEXT NOT NULL DEFAULT '',
  template TEXT,
  repost_label TEXT,
  status TEXT NOT NULL DEFAULT 'published' CHECK(status IN ('published','hidden','deleted')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_feed_videos_feed ON feed_videos(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_feed_videos_user ON feed_videos(user_id, created_at DESC);
CREATE TABLE IF NOT EXISTS feed_video_likes (
  video_id TEXT NOT NULL REFERENCES feed_videos(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  PRIMARY KEY(video_id,user_id)
);
CREATE TABLE IF NOT EXISTS feed_video_saves (
  video_id TEXT NOT NULL REFERENCES feed_videos(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  PRIMARY KEY(video_id,user_id)
);
CREATE TABLE IF NOT EXISTS feed_video_shares (
  id TEXT PRIMARY KEY,
  video_id TEXT NOT NULL REFERENCES feed_videos(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS feed_video_comments (
  id TEXT PRIMARY KEY,
  video_id TEXT NOT NULL REFERENCES feed_videos(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content TEXT NOT NULL CHECK(length(content) BETWEEN 1 AND 500),
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_feed_comments_video ON feed_video_comments(video_id,created_at DESC);
CREATE TABLE IF NOT EXISTS feed_comment_likes (
  comment_id TEXT NOT NULL REFERENCES feed_video_comments(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  PRIMARY KEY(comment_id,user_id)
);
CREATE TABLE IF NOT EXISTS feed_video_sends (
  id TEXT PRIMARY KEY,
  video_id TEXT NOT NULL REFERENCES feed_videos(id) ON DELETE CASCADE,
  sender_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  recipient_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_feed_sends_recipient ON feed_video_sends(recipient_id,created_at DESC);
