-- Relational identity for independent admin actions in the audit log.
-- The table is additive and safe to re-apply during deployment retries.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS admin_audit_actor_refs (
  audit_log_id TEXT PRIMARY KEY REFERENCES admin_audit_logs(id) ON DELETE CASCADE,
  admin_id TEXT NOT NULL REFERENCES admin_accounts(id) ON DELETE RESTRICT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_actor_refs_admin_created
  ON admin_audit_actor_refs(admin_id, created_at DESC);

-- Backfill legacy admin audit rows whose actor identity was stored in details_json.
-- Invalid JSON and unknown account ids are ignored without blocking deployment.
INSERT OR IGNORE INTO admin_audit_actor_refs (audit_log_id, admin_id)
SELECT l.id,
       CASE WHEN json_valid(l.details_json) = 1
            THEN json_extract(l.details_json, '$.adminId')
            ELSE NULL
       END
FROM admin_audit_logs l
WHERE json_valid(l.details_json) = 1
  AND json_extract(l.details_json, '$.adminId') IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM admin_accounts a
    WHERE a.id = CASE WHEN json_valid(l.details_json) = 1
                      THEN json_extract(l.details_json, '$.adminId')
                      ELSE NULL
                 END
  );
