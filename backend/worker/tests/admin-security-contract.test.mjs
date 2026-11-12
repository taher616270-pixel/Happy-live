import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const worker = await readFile(new URL("../src/index.ts", import.meta.url), "utf8");
const adminUi = await readFile(
  new URL("../../../frontend/web/admin/index.html", import.meta.url),
  "utf8",
);
const appMain = await readFile(
  new URL("../../../frontend/lib/main.dart", import.meta.url),
  "utf8",
);
const walletPage = await readFile(
  new URL("../../../frontend/lib/pages/wallet_page.dart", import.meta.url),
  "utf8",
);
const profilePage = await readFile(
  new URL("../../../frontend/lib/pages/profile_page.dart", import.meta.url),
  "utf8",
);
const auditMigration = await readFile(new URL("../migrations/0031_admin_audit_actor_refs.sql", import.meta.url), "utf8");

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
  // Ignore native HTML <select> elements; the SQL guard is intended to
  // detect database statements in the browser code, not form controls.
  const adminUiWithoutSelectTags = adminUi.replace(/<select\b[^>]*>/gi, " ");
  assert.doesNotMatch(
    adminUiWithoutSelectTags,
    /\b(?:D1Database|SELECT\s+\w+|INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM)\b/i,
  );
});

test("wallet administration uses the server-backed wallet ledger and owner-only credit route", () => {
  assert.match(worker, /url\.pathname === "\/api\/v1\/admin\/wallets"/);
  assert.match(worker, /url\.pathname === "\/api\/v1\/wallet"/);
  assert.match(worker, /wallet_transactions/);
  assert.match(worker, /actor\.role !== "owner".*إضافة العملات متاحة لمالك التطبيق فقط/s);
  assert.match(worker, /VALUES \(\?, NULL, 'wallet\.credit', 'user', \?, \?, \?\)/);
  assert.match(adminUi, /async function walletsPage\(/);
  assert.match(adminUi, /input\.focus\(\);input\.setSelectionRange\(value\.length,value\.length\)/);
  assert.match(adminUi, /\/admin\/users\/.*\/wallet\/credit/);
  assert.doesNotMatch(adminUi, /VIP والشحن والهدايا والمحفظة لا تملك جداول أو نقاط API حقيقية/);
});

test("mobile wallet is connected to the authenticated wallet API and profile balance", () => {
  assert.match(appMain, /import 'pages\/wallet_page\.dart';/);
  assert.match(appMain, /WalletPage\(apiBase: _apiBase, accessToken: widget\.accessToken\)/);
  assert.match(appMain, /onWallet: _openWallet/);
  assert.match(appMain, /balance: _walletBalance/);
  assert.match(profilePage, /balance: balance/);
  assert.match(walletPage, /Uri\.parse\('\$\{widget\.apiBase\}\/wallet'\)/);
  assert.match(walletPage, /Authorization': 'Bearer \$\{widget\.accessToken\}'/);
  assert.match(walletPage, /item\['balanceAfter'\]/);
});

test("unsupported electronic recharge and VIP are clearly disabled while gift history is real", () => {
  assert.match(adminUi, /إدارة VIP والشحن الإلكتروني غير مفعّلة/);
  assert.match(adminUi, /سجل إرسال الهدايا/);
  assert.match(worker, /gift_transactions/);
});


test("admin account management is owner-only, protects the owner, and revokes sessions", () => {
  const start = worker.indexOf('if (url.pathname === "/api/v1/admin/accounts" && request.method === "GET")');
  const end = worker.indexOf('if (url.pathname === "/api/v1/admin/moderators"', start);
  assert.ok(start >= 0 && end > start, "admin account routes must exist");
  const routes = worker.slice(start, end);
  assert.match(routes, /actor\\.role !== "owner"/);
  assert.match(routes, /target\\.role === "owner"/);
  assert.match(routes, /hashPassword\\(password\\)/);
  assert.match(routes, /UPDATE admin_sessions SET revoked_at = \\?/);
  assert.match(routes, /adminAuditStatements\\(env\\.DB, actor,/);
  assert.doesNotMatch(routes, /body\\.(?:adminId|actorId|actorRole)/);
});

test("admin audit relation links sensitive manager actions to the authenticated admin", () => {
  assert.match(auditMigration, /CREATE TABLE IF NOT EXISTS admin_audit_actor_refs/);
  assert.match(auditMigration, /REFERENCES admin_audit_logs\\(id\\) ON DELETE CASCADE/);
  assert.match(auditMigration, /REFERENCES admin_accounts\\(id\\) ON DELETE RESTRICT/);
  assert.match(worker, /function adminAuditStatements\\(/);
  assert.match(worker, /INSERT INTO admin_audit_actor_refs/);
  assert.match(adminUi, /data-page="adminAccounts"/);
  assert.match(adminUi, /admin\\.role!==\\"owner\\"/);
  assert.match(adminUi, /api\\(\\"\\/admin\\/accounts/);
});
