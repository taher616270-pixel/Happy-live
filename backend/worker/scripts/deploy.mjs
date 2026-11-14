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
if (/"name"\s*:\s*"gabo_id"/.test(schemaOutput)) {
  run([
    ...common,
    "--file",
    "migrations/0043_rename_gabo_id_to_happy_id.sql",
    "--config",
    "wrangler.toml",
  ]);
} else if (!/"name"\s*:\s*"happy_id"/.test(schemaOutput)) {
  throw new Error("Could not verify the public player ID column; refusing to deploy.");
}

run(["deploy", "--config", "wrangler.toml"]);
