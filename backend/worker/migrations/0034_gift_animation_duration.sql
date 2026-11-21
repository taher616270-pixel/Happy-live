ALTER TABLE gift_catalog ADD COLUMN duration_seconds INTEGER NOT NULL DEFAULT 5 CHECK (duration_seconds BETWEEN 1 AND 60);
