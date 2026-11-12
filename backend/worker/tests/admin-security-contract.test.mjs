import test from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
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
const workerOnlyDeployWorkflow = await readFile(
  new URL("../../../.github/workflows/deploy-happy-live-worker-only.yml", import.meta.url),
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
  const walletRouteStart = worker.indexOf("const adminWalletCreditRoute =");
  const walletRouteEnd = worker.indexOf('if (url.pathname === "/api/v1/admin/agora/voice"', walletRouteStart);
  assert.ok(walletRouteStart >= 0 && walletRouteEnd > walletRouteStart, "wallet credit route must exist");
  const walletRoute = worker.slice(walletRouteStart, walletRouteEnd);
  assert.match(walletRoute, /actor\.role !== "owner"/);
  assert.match(walletRoute, /INSERT INTO wallet_transactions/);
  assert.match(walletRoute, /'admin_credit'/);
  assert.match(walletRoute, /action: "wallet\.credit"/);
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

test("unsupported recharge, VIP and gift services are not presented as live data", () => {
  assert.match(adminUi, /الشحن الإلكتروني عبر بوابة دفع غير مفعّل بعد/);
});


test("admin account management is owner-only, protects the owner, and revokes sessions", () => {
  const start = worker.indexOf('if (url.pathname === "/api/v1/admin/accounts" && request.method === "GET")');
  const end = worker.indexOf('if (url.pathname === "/api/v1/admin/moderators"', start);
  assert.ok(start >= 0 && end > start, "admin account routes must exist");
  const routes = worker.slice(start, end);
  assert.match(routes, /actor\.role !== "owner"/);
  assert.match(routes, /target\.role === "owner" \|\| target\.username\.toLowerCase\(\) === "owner"/);
  assert.match(routes, /hashPassword\(password\)/);
  assert.match(routes, /UPDATE admin_sessions SET revoked_at = \?/);
  assert.match(routes, /adminAuditStatements\(env\.DB, actor,/);
  assert.doesNotMatch(routes, /body\.(?:adminId|actorId|actorRole)/);
});

test("admin audit records use a relational manager reference", () => {
  assert.match(auditMigration, /CASE WHEN json_valid\(l\.details_json\) = 1/);
  assert.match(auditMigration, /a\.id = CASE WHEN json_valid\(l\.details_json\) = 1/);
  assert.match(auditMigration, /REFERENCES admin_audit_logs\(id\) ON DELETE CASCADE/);
  assert.match(auditMigration, /REFERENCES admin_accounts\(id\) ON DELETE RESTRICT/);
  const start = worker.indexOf("function adminAuditStatements(");
  const end = worker.indexOf("const DEFAULT_ALLOWED_ORIGINS", start);
  assert.ok(start >= 0 && end > start, "relational audit helper must exist");
  const helper = worker.slice(start, end);
  assert.match(helper, /INSERT INTO admin_audit_logs/);
  assert.match(helper, /INSERT INTO admin_audit_actor_refs/);
  assert.match(worker, /LEFT JOIN admin_audit_actor_refs ar ON ar\.audit_log_id = l\.id/);
});

test("admin CORS trusts only exact configured origins", () => {
  const start = worker.indexOf("function isAllowedOrigin(");
  const end = worker.indexOf("function json(", start);
  assert.ok(start >= 0 && end > start);
  const validator = worker.slice(start, end);
  assert.match(validator, /return allowedOrigins\(env\)\.has\(origin\);/);
  assert.doesNotMatch(validator, /endsWith|new URL/);
});

test("admin account UI is owner-only and uses the authenticated Worker API", () => {
  assert.match(adminUi, /data-page="adminAccounts"/);
  assert.match(adminUi, /admin\.role!==\"owner\"/);
  assert.match(adminUi, /api\(\"\/admin\/accounts/);
  assert.match(adminUi, /\/admin\/accounts\/.*\/password/);
});


test("every sensitive admin audit write records a relational actor reference", () => {
  const start = worker.indexOf("// Admin API: authentication uses a separate admin-only session table.");
  const end = worker.indexOf('if (url.pathname === "/api/v1/auth/google"', start);
  assert.ok(start >= 0 && end > start, "admin API block must exist");
  const adminRoutes = worker.slice(start, end);
  assert.doesNotMatch(adminRoutes, /INSERT INTO admin_audit_logs/);
  assert.match(adminRoutes, /adminAuditStatements\(env\.DB, actor,/);
  for (const action of [
    "wallet.credit",
    "agora.voice.enable",
    "agora.voice.disable",
    "user.kick",
    "user.suspend",
    "user.activate",
    "room.close",
    "room.reopen",
    "room.user.mute",
    "room.user.unmute"
  ]) assert.ok(adminRoutes.includes(action), `expected audited action ${action}`);
});

test("migration backfills legacy admin actor ids from valid audit JSON", () => {
  assert.match(auditMigration, /json_valid\(l\.details_json\) = 1/);
  assert.match(auditMigration, /json_extract\(l\.details_json, '\$\.adminId'\)/);
  assert.match(auditMigration, /EXISTS \([\s\S]*FROM admin_accounts a[\s\S]*a\.id = json_extract/);
});


test("gift catalogue and custom-request administration are owner-audited", () => {
  const start = worker.indexOf('if (url.pathname === "/api/v1/admin/gifts/settings"');
  const end = worker.indexOf('if (url.pathname === "/api/v1/admin/moderators"', start);
  assert.ok(start >= 0 && end > start, "gift administration routes must exist");
  const routes = worker.slice(start, end);
  for (const action of [
    "gift.catalog.create",
    "gift.catalog.update",
    "gift.catalog.deactivate",
    "gift.custom_request.approve",
    "gift.custom_request.reject"
  ]) assert.ok(routes.includes(action), `expected audit action ${action}`);
  assert.match(routes, /actor\.role !== "owner"/);
  assert.match(routes, /adminAuditStatements\(env\.DB, actor,/);
});


test("admin audit migration is idempotent and ignores malformed or unknown legacy actors", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec("CREATE TABLE admin_accounts (id TEXT PRIMARY KEY); CREATE TABLE admin_audit_logs (id TEXT PRIMARY KEY, details_json TEXT NOT NULL);");
    db.exec("INSERT INTO admin_accounts (id) VALUES ('owner')");
    db.exec("INSERT INTO admin_audit_logs (id, details_json) VALUES ('valid', '{\"adminId\":\"owner\"}'), ('malformed', 'not-json'), ('unknown', '{\"adminId\":\"missing\"}')");
    db.exec(auditMigration);
    db.exec(auditMigration);
    const rows = db.prepare("SELECT audit_log_id, admin_id FROM admin_audit_actor_refs ORDER BY audit_log_id").all();
    assert.deepEqual(rows, [{ audit_log_id: "valid", admin_id: "owner" }]);
    assert.throws(() => db.prepare("DELETE FROM admin_accounts WHERE id = ?").run("owner"), /FOREIGN KEY constraint failed/);
    db.prepare("DELETE FROM admin_audit_logs WHERE id = ?").run("valid");
    assert.equal(db.prepare("SELECT COUNT(*) AS count FROM admin_audit_actor_refs").get().count, 0);
  } finally {
    db.close();
  }
});

test("manual worker-only deployment checks the audit migration before deploying", () => {
  const guardStart = workerOnlyDeployWorkflow.indexOf("Verify required admin audit migration");
  const deployStart = workerOnlyDeployWorkflow.indexOf("Deploy Worker only");
  assert.ok(guardStart >= 0 && deployStart > guardStart, "migration guard must run before the worker-only deploy");
  const guard = workerOnlyDeployWorkflow.slice(guardStart, deployStart);
  assert.match(guard, /wrangler d1 execute happy-live-db --remote/);
  assert.match(guard, /admin_audit_actor_refs/);
  assert.match(guard, /grep -q/);
  assert.match(guard, /exit 1/);
});