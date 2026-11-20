PRAGMA foreign_keys = ON;

-- Freeze the contributors for each launch so later launches never inherit
-- amounts from earlier rounds.
CREATE TABLE IF NOT EXISTS cannon_launch_contributors (
  launch_id TEXT NOT NULL REFERENCES cannon_launches(id) ON DELETE CASCADE,
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  contribution INTEGER NOT NULL CHECK (contribution > 0),
  PRIMARY KEY (launch_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_cannon_launch_contributors_rank
  ON cannon_launch_contributors(launch_id, contribution DESC);
