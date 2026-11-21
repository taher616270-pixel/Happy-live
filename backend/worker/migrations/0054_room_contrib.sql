-- Room contributor rankings (Saudi Arabia local periods).
CREATE TABLE IF NOT EXISTS room_contrib (
  room_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  period TEXT NOT NULL CHECK (period IN ('daily', 'weekly', 'monthly')),
  pkey TEXT NOT NULL,
  amount INTEGER NOT NULL DEFAULT 0 CHECK (amount >= 0),
  PRIMARY KEY (room_id, user_id, period, pkey)
);

CREATE INDEX IF NOT EXISTS idx_room_contrib_top
  ON room_contrib (room_id, period, pkey, amount DESC);
