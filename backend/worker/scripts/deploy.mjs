import { spawnSync } from "node:child_process";

const result = spawnSync("npx", ["wrangler", "deploy", "--config", "wrangler.toml"], {
  cwd: process.cwd(),
  encoding: "utf8",
  stdio: "inherit",
});

if (result.status !== 0) {
  throw new Error("Worker deployment failed.");
}
