-- Relational identity for independent admin actions in the audit log.
-- Idempotent so a deployment retry does not duplicate or rewrite audit history.
CREATE TABLE IF NOT EXISTS admin_audit_actor_refs (
  audit_log_id TEXT PRIMARY KEY REFERENCES admin_audit_logs(id) ON DELETE CASCADE,
  admin_id TEXT NOT NULL REFERENCES admin_accounts(id) ON DELETE RESTRICT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_actor_refs_admin_created
  ON admin_audit_actor_refs(admin_id, created_at DESC);
