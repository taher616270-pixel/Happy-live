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
  // Admin wallet history must include Food Wheel bets and payouts, not only
  // the generic wallet_transactions table.
  assert.match(worker, /FROM wallet_transactions WHERE user_id = \\? \\" \\+\\s*\\"UNION ALL\\" \\+\\s*\\"SELECT id, amount, balance_after AS balanceAfter, transaction_type AS type, round_id AS referenceId, description, created_at AS createdAt\\" \\+\\s*\\"FROM cat_greed_ledger WHERE user_id = \\? /s);
  assert.match(worker, /\\.bind\\(userId, userId\\)\\.all\\(\\)/);
  assert.match(worker, /actor\\.role !== "owner".*إضافة العملات متاحة لمالك التطبيق فقط/s);
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

test("unsupported recharge, VIP and gift services are not presented as live data", () => {
  assert.match(adminUi, /الشحن الإلكتروني عبر بوابة دفع غير مفعّل بعد/);
});
