import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const worker = await readFile(new URL("../src/index.ts", import.meta.url), "utf8");
const migration = await readFile(new URL("../migrations/0023_admin_account_roles.sql", import.meta.url), "utf8");
const adminPage = await readFile(new URL("../../../frontend/web/admin/index.html", import.meta.url), "utf8");

test("administrator role is loaded from D1 and is not hardcoded as owner", () => {
  assert.match(worker, /INNER JOIN admin_account_roles r ON r\.admin_id = a\.id/);
  assert.match(worker, /role: row\.role as AdminRole/);
  assert.doesNotMatch(worker, /const role = "owner" as const/);
});

test("sensitive routes have server-side permission checks", () => {
  assert.match(worker, /hasAdminPermission\(actor, "users\.manage"\)/);
  assert.match(worker, /hasAdminPermission\(actor, "users\.kick"\)/);
  assert.match(worker, /hasAdminPermission\(actor, "users\.roles\.manage"\)/);
  assert.match(worker, /hasAdminPermission\(actor, "rooms\.manage"\)/);
  assert.match(worker, /hasAdminPermission\(actor, "agora\.manage"\)/);
});

test("account suspension and kick revoke sessions and are auditable", () => {
  assert.match(worker, /UPDATE user_sessions SET revoked_at = \? WHERE user_id = \? AND revoked_at IS NULL/);
  assert.match(worker, /DELETE FROM room_seats WHERE user_id = \?/);
  assert.match(worker, /'user\.kick'/);
  assert.match(worker, /adminUsername: actor\.username/);
});

test("console roles are constrained and primary owner is seeded", () => {
  assert.match(migration, /CHECK \(role IN \('owner', 'admin', 'moderator'\)\)/);
  assert.match(migration, /SELECT id, 'owner' FROM admin_accounts/);
});

test("standalone admin page exposes stats and moderator management without fake economy data", () => {
  assert.match(adminPage, /data-page="stats"/);
  assert.match(adminPage, /data-page="moderators"/);
  assert.match(adminPage, /VIP والشحن والهدايا/);
});
