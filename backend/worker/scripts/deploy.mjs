import { spawnSync } from "node:child_process";

const run = (args) => {
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
};

const database = "happy-live-db";
const common = ["d1", "execute", database, "--remote"];

for (const migration of [
  "migrations/0040_game_registry_status.sql",
  "migrations/0041_game_sessions.sql",
  "migrations/0042_game_session_app_binding.sql",
]) {
  run([...common, "--file", migration, "--config", "wrangler.toml"]);
}

const schemaOutput = run([
  ...common,
  "--command",
  "PRAGMA table_info(profiles)",
  "--json",
  "--config",
  "wrangler.toml",
]);
const hasHappyId = /"name"\s*:\s*"happy_id"/.test(schemaOutput);
const hasLegacyId = /"name"\s*:\s*"gabo_id"/.test(schemaOutput);
if (!hasHappyId && hasLegacyId) {
  run([
    ...common,
    "--file",
    "migrations/0043_rename_gabo_id_to_happy_id.sql",
    "--config",
    "wrangler.toml",
  ]);
} else if (!hasHappyId) {
  throw new Error("Could not verify the public player ID column; refusing to deploy.");
} else if (!hasLegacyId) {
  run([
    ...common,
    "--command",
    "ALTER TABLE profiles ADD COLUMN gabo_id TEXT; UPDATE profiles SET gabo_id = happy_id; CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_gabo_id_compat ON profiles(gabo_id) WHERE gabo_id IS NOT NULL AND gabo_id <> ''; CREATE TRIGGER IF NOT EXISTS profiles_sync_happy_id_to_legacy AFTER UPDATE OF happy_id ON profiles WHEN NEW.happy_id IS NOT OLD.happy_id BEGIN UPDATE profiles SET gabo_id = NEW.happy_id WHERE user_id = NEW.user_id; END; CREATE TRIGGER IF NOT EXISTS profiles_sync_legacy_to_happy_id AFTER UPDATE OF gabo_id ON profiles WHEN NEW.gabo_id IS NOT OLD.gabo_id BEGIN UPDATE profiles SET happy_id = NEW.gabo_id WHERE user_id = NEW.user_id; END;",
    "--config",
    "wrangler.toml",
  ]);
}

run(["deploy", "--config", "wrangler.toml"]);
