import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const worker = await readFile(new URL("../src/index.ts", import.meta.url), "utf8");
const adminUi = await readFile(
  new URL("../../../frontend/web/admin/index.html", import.meta.url),
  "utf8",
);
const auditMigration = await readFile(
  new URL("../migrations/0024_admin_audit_actor_refs.sql", import.meta.url),
  "utf8",
);

test("admin sessions and roles are resolved from D1, not from browser input", () => {
  const start = worker.indexOf("async function authenticatedAdmin(");
  const end = worker.indexOf("async function createAdminSession(", start);
  assert.ok(start >= 0 && end > start, "admin authentication function must exist");

  const authFunction = worker.slice(start, end);
  assert.match(authFunction, /FROM admin_sessions s INNER JOIN admin_accounts a/);
  assert.match(authFunction, /INNER JOIN admin_account_roles r/);
  assert.match(authFunction, /s\.token_hash = \?/);
  assert.doesNotMatch(authFunction, /request\.json|body\.role/);
  assert.match(
    worker,
    /function hasAdminPermission\(actor: AdminActor, permission: AdminPermission\): boolean \{\s*return actor\.role === "owner" \|\| ADMIN_ROLE_PERMISSIONS\[actor\.role\]\.has\(permission\);/s,
  );
});

test("admin API routes require a server-validated session and permission checks", () => {
  const start = worker.indexOf(
    "// Admin API: authentication uses a separate admin-only session table.",
  );
  const end = worker.indexOf(
    'if (url.pathname === "/api/v1/auth/google"',
    start,
  );
  assert.ok(start >= 0 && end > start, "admin API route block must exist");

  const adminRoutes = worker.slice(start, end);
  assert.match(
    adminRoutes,
    /const actor = await authenticatedAdmin\(request, env\.DB\)/,
  );
  assert.match(
    adminRoutes,
    /if \(!actor\) return json\(\{ error: "authentication_required" \}/,
  );
  assert.match(adminRoutes, /hasAdminPermission\(actor,/);
});

test("sensitive admin operations record the acting admin in the audit payload", () => {
  assert.match(worker, /admin_audit_logs/);
  assert.match(worker, /adminUsername: actor\.username/);
  assert.match(worker, /adminId: actor\.id/);
});

test("the admin browser uses the Worker API and never queries D1 directly", () => {
  assert.match(
    adminUi,
    /const API="https:\/\/happy-live-api\.taher616270\.workers\.dev\/api\/v1"/,
  );
  assert.match(adminUi, /fetch\(API\+path/);
  assert.match(
    adminUi,
    /["']Authorization["']\s*:\s*["']Bearer ["']\s*\+\s*token/,
  );
  assert.doesNotMatch(
    adminUi,
    /\b(?:D1Database|SELECT\s+\w+|INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM)\b/i,
  );
});

test("unsupported VIP, wallet, recharge and gift services are not presented as live data", () => {
  assert.match(
    adminUi,
    /VIP والشحن والهدايا والمحفظة لا تملك جداول أو نقاط API حقيقية/,
  );
});


test("CORS trusts only explicitly configured origins, not arbitrary Pages subdomains", () => {
  const start = worker.indexOf("function isAllowedOrigin(");
  const end = worker.indexOf("function json(", start);
  assert.ok(start >= 0 && end > start, "CORS origin validator must exist");
  const validator = worker.slice(start, end);
  assert.match(validator, /return allowedOrigins\(env\)\.has\(origin\);/);
  assert.doesNotMatch(validator, /endsWith|new URL/);
  assert.match(worker, /"https:\/\/happy-live\.pages\.dev"/);
});

test("new admin audit entries have a relational link to the acting admin", () => {
  assert.match(auditMigration, /CREATE TABLE IF NOT EXISTS admin_audit_actor_refs/);
  assert.match(auditMigration, /REFERENCES admin_audit_logs\(id\) ON DELETE CASCADE/);
  assert.match(auditMigration, /REFERENCES admin_accounts\(id\) ON DELETE RESTRICT/);
  assert.match(auditMigration, /CREATE INDEX IF NOT EXISTS/);

  const helperStart = worker.indexOf("function adminAuditStatements(");
  const helperEnd = worker.indexOf("const DEFAULT_ALLOWED_ORIGINS", helperStart);
  assert.ok(helperStart >= 0 && helperEnd > helperStart, "admin audit helper must exist");
  const helper = worker.slice(helperStart, helperEnd);
  assert.match(helper, /INSERT INTO admin_audit_logs/);
  assert.match(helper, /INSERT INTO admin_audit_actor_refs/);
  assert.match(helper, /bind\(auditId, actor\.id\)/);
  assert.match(worker, /LEFT JOIN admin_audit_actor_refs ar ON ar\.audit_log_id = l\.id/);
  assert.match(worker, /LEFT JOIN admin_accounts aa ON aa\.id = ar\.admin_id/);
});

test("all sensitive admin routes use the relational audit helper", () => {
  const start = worker.indexOf(
    "// Admin API: authentication uses a separate admin-only session table.",
  );
  const end = worker.indexOf('if (url.pathname === "/api/v1/auth/google"', start);
  assert.ok(start >= 0 && end > start, "admin API route block must exist");
  const routes = worker.slice(start, end);
  assert.equal((routes.match(/adminAuditStatements\(env\.DB, actor/g) || []).length, 6);
  for (const action of [
    "agora.voice.enable",
    "agora.voice.disable",
    "user.role.assign",
    "user.suspend",
    "user.kick",
    "room.user.ban",
    "room.user.kick",
    "room.close",
  ]) {
    assert.ok(routes.includes(action), `expected auditable action ${action}`);
  }
});
