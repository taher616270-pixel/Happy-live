-- Room tools: owner/moderator controlled room lock.
-- Historical kick entries reuse admin_audit_logs; room_kicks remains the active
-- temporary-kick restriction table created by migration 0015.
ALTER TABLE rooms ADD COLUMN locked INTEGER NOT NULL DEFAULT 0;
