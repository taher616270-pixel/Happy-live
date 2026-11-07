-- Server-side roles for independent console sessions.
CREATE TABLE IF NOT EXISTS admin_account_roles (
  admin_id TEXT PRIMARY KEY REFERENCES admin_accounts(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('owner', 'admin', 'moderator')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
CREATE INDEX IF NOT EXISTS idx_admin_account_roles_role ON admin_account_roles(role);
INSERT OR IGNORE INTO admin_account_roles (admin_id, role)
SELECT id, 'owner' FROM admin_accounts WHERE username = 'owner' COLLATE NOCASE;
