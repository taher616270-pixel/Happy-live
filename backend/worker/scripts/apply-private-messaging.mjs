import { spawnSync } from "node:child_process";

const database = "happy-live-db";
const config = "wrangler.toml";
const migration = "migrations/0044_private_messaging.sql";

function run(args) {
  const result = spawnSync("npx", ["wrangler", ...args], {
    cwd: process.cwd(),
    encoding: "utf8",
    stdio: ["ignore", "pipe", "inherit"],
  });
  if (result.status !== 0) {
    process.stderr.write(result.stdout || "");
    throw new Error(`wrangler ${args.join(" ")} failed`);
  }
  return result.stdout || "";
}

function readJsonRows(output) {
  const parsed = JSON.parse(output);
  const queue = [parsed];
  while (queue.length) {
    const value = queue.shift();
    if (!value || typeof value !== "object") continue;
    if (Array.isArray(value)) {
      if (value.every((item) => item && typeof item === "object")) {
        const rows = value.filter((item) => Object.hasOwn(item, "name") || Object.hasOwn(item, "table_name"));
        if (rows.length) return rows;
      }
      queue.push(...value);
    } else {
      queue.push(...Object.values(value));
    }
  }
  return [];
}

const query = (sql) => run(["d1", "execute", database, "--remote", "--command", sql, "--json", "--config", config]);

const existing = readJsonRows(query(
  "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('users','profiles','user_sessions','conversations','conversation_members','private_messages') ORDER BY name"
));
const names = new Set(existing.map((row) => row.name ?? row.table_name));
for (const required of ["users", "profiles", "user_sessions"]) {
  if (!names.has(required)) throw new Error(`Required production table missing: ${required}. No migration was run.`);
}

const messagingTables = ["conversations", "conversation_members", "private_messages"];
const present = messagingTables.filter((name) => names.has(name));
if (present.length !== 0 && present.length !== messagingTables.length) {
  throw new Error("Partial private-messaging schema detected. Refusing automatic repair; inspect D1 before proceeding.");
}

if (present.length === 0) {
  run(["d1", "execute", database, "--remote", "--file", migration, "--config", config]);
}

query(
  "INSERT INTO d1_migrations (id, name, applied_at) SELECT COALESCE((SELECT MAX(id) FROM d1_migrations), 0) + 1, '0044_private_messaging.sql', datetime('now') WHERE NOT EXISTS (SELECT 1 FROM d1_migrations WHERE name='0044_private_messaging.sql')"
);

const verify = readJsonRows(query(
  "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('conversations','conversation_members','private_messages') ORDER BY name"
));
const verified = new Set(verify.map((row) => row.name ?? row.table_name));
if (messagingTables.some((name) => !verified.has(name))) {
  throw new Error("Private-messaging migration verification failed.");
}

process.stdout.write("Private-messaging migration 0044 is applied and verified.\\n");
