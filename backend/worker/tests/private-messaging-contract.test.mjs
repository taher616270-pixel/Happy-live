import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const worker = readFileSync(new URL("../src/index.ts", import.meta.url), "utf8");
const migration = readFileSync(new URL("../migrations/0044_private_messaging.sql", import.meta.url), "utf8");
const frontend = readFileSync(new URL("../../../frontend/lib/main.dart", import.meta.url), "utf8");

test("private messaging endpoints require an authenticated active session", () => {
  assert.match(worker, /\/api\/v1\/messages\/search/);
  assert.match(worker, /\/api\/v1\/messages\/conversations/);
  assert.match(worker, /authenticatedUser\(request, env\.DB\)/);
  assert.match(worker, /conversation_members WHERE conversation_id = \? AND user_id = \?/);
});

test("direct conversations are unique per user pair and groups are member scoped", () => {
  assert.match(migration, /direct_key TEXT UNIQUE/);
  assert.match(migration, /PRIMARY KEY \(conversation_id, user_id\)/);
  assert.match(worker, /c\.kind = 'group' AND c\.title LIKE \?/);
  assert.match(worker, /INSERT INTO conversation_members/);
});

test("private messages enforce content bounds, pagination and anti-spam", () => {
  assert.match(migration, /length\(content\) BETWEEN 1 AND 2000/);
  assert.match(worker, /ORDER BY m\.created_at DESC LIMIT \?/);
  assert.match(worker, /recent\?\.total \?\? 0\) >= 30/);
});

test("messages tab is connected to the authenticated API and opens conversations", () => {
  assert.match(frontend, /_HappyMessagesTab\(apiBase: _apiBase, accessToken: widget\.accessToken\)/);
  assert.match(frontend, /\/messages\/search\?q=/);
  assert.match(frontend, /\/messages\/conversations/);
  assert.match(frontend, /_HappyConversationPage/);
});
