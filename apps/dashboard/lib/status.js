/*
 * Status + control helpers for sub-apps.
 *
 * "Installed" is read from the repo-root `.installed` marker file (the
 * same one apps/cli/scripts/lib/common.sh's mark_installed/is_installed
 * maintain) - one app id per line.
 *
 * "Running" is determined from actual podman container state for that
 * app's compose project (labels `io.podman.compose.project=<id>`),
 * mirroring common.sh's app_containers_healthy - this is more reliable
 * than an HTTP reachability check (which can't tell "still starting up"
 * from "not installed" from "crashed").
 *
 * Start/stop simply invoke the app's own up.sh/down.sh - the dashboard
 * never calls podman-compose directly, so every app's own idempotent
 * install contract (ensure_env_file, etc.) still applies unchanged.
 */

const fs = require("node:fs");
const path = require("node:path");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");

const execFileAsync = promisify(execFile);

const INSTALLED_MARKER_FILE = (catasophieRoot) => path.join(catasophieRoot, ".installed");

function isInstalled(catasophieRoot, appId) {
  const markerFile = INSTALLED_MARKER_FILE(catasophieRoot);
  if (!fs.existsSync(markerFile)) return false;
  const lines = fs
    .readFileSync(markerFile, "utf8")
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean);
  return lines.includes(appId);
}

// Returns "running" if at least one container in the app's compose
// project is in state "running", "stopped" if the project has
// containers but none running, or "unknown" if podman itself failed
// (e.g. not installed on this host) - callers should treat "unknown"
// like "stopped" for display purposes but surface the error.
async function containerState(appId) {
  try {
    const { stdout } = await execFileAsync("podman", [
      "ps",
      "-a",
      "--filter",
      `label=io.podman.compose.project=${appId}`,
      "--format",
      "{{.State}}"
    ]);
    const states = stdout
      .split("\n")
      .map((s) => s.trim())
      .filter(Boolean);
    if (states.length === 0) return "stopped";
    return states.includes("running") ? "running" : "stopped";
  } catch (err) {
    return "unknown";
  }
}

// Full status for one configured app: "not-installed" | "stopped" | "running".
async function appStatus(catasophieRoot, appId) {
  if (!isInstalled(catasophieRoot, appId)) return "not-installed";
  const state = await containerState(appId);
  if (state === "running") return "running";
  return "stopped";
}

async function statusesFor(catasophieRoot, apps) {
  const entries = await Promise.all(
    apps.map(async (app) => [app.id, await appStatus(catasophieRoot, app.id)])
  );
  return Object.fromEntries(entries);
}

// Runs apps/<id>/up.sh or down.sh, resolved relative to catasophieRoot.
// Rejects if the app isn't installed or the script is missing, so callers
// never need to shell-interpolate an arbitrary id.
async function runAppScript(catasophieRoot, appId, script) {
  if (!["up.sh", "down.sh"].includes(script)) {
    throw new Error(`refusing to run unexpected script: ${script}`);
  }
  const appDir = path.join(catasophieRoot, "apps", appId);
  const scriptPath = path.join(appDir, script);
  if (!fs.existsSync(scriptPath)) {
    throw new Error(`${script} not found for app "${appId}" - is it installed?`);
  }
  const { stdout, stderr } = await execFileAsync("bash", [scriptPath], {
    cwd: appDir,
    timeout: 5 * 60 * 1000
  });
  return { stdout, stderr };
}

async function startApp(catasophieRoot, appId) {
  return runAppScript(catasophieRoot, appId, "up.sh");
}

async function stopApp(catasophieRoot, appId) {
  return runAppScript(catasophieRoot, appId, "down.sh");
}

module.exports = {
  isInstalled,
  containerState,
  appStatus,
  statusesFor,
  startApp,
  stopApp
};
