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
const crypto = require("node:crypto");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");

const execFileAsync = promisify(execFile);

const INSTALLED_MARKER_FILE = (catasophieRoot) => path.join(catasophieRoot, ".installed");

// Third-party apps (id "external/<name>", see apps/external/README.md and
// docs/EXTERNAL_APPS.md) live under apps/external/<name> instead of
// apps/<name>, and their podman-compose project name is just <name> (the
// compose file's own directory name), not the full "external/<name>" id -
// mirrors apps/cli/scripts/lib/common.sh's _app_dir_for/_project_name_for.
function isExternal(appId) {
  return appId.startsWith("external/");
}

function appDirFor(catasophieRoot, appId) {
  if (isExternal(appId)) {
    return path.join(catasophieRoot, "apps", "external", appId.slice("external/".length));
  }
  return path.join(catasophieRoot, "apps", appId);
}

function projectNameFor(appId) {
  return isExternal(appId) ? appId.slice("external/".length) : appId;
}

// Same review-relevant file list + hash as external.sh's
// _external_review_targets/_external_review_hash - kept in sync by hand
// since one side is bash and the other Node. Used only to tell the
// dashboard whether an external app is safe to start (it never performs
// the review itself - that's a CLI-only step, see
// apps/cli/scripts/review-external.sh).
const REVIEW_FILES = ["docker-compose.yml", "install.sh", "uninstall.sh", "up.sh", "down.sh", ".env.example"];

function externalReviewHash(appDir) {
  const hashes = REVIEW_FILES
    .filter((f) => fs.existsSync(path.join(appDir, f)))
    .sort()
    .map((f) => crypto.createHash("sha256").update(fs.readFileSync(path.join(appDir, f))).digest("hex"))
    .join("");
  return crypto.createHash("sha256").update(hashes).digest("hex");
}

function isExternalReviewed(appDir) {
  const reviewFile = path.join(appDir, ".reviewed");
  if (!fs.existsSync(reviewFile)) return false;
  return fs.readFileSync(reviewFile, "utf8").trim() === externalReviewHash(appDir);
}

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
      `label=io.podman.compose.project=${projectNameFor(appId)}`,
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

// Full status for one configured app: "not-installed" | "stopped" |
// "running" | "needs-review" (external apps only - see
// apps/external/README.md; blocks start until reviewed/re-reviewed).
async function appStatus(catasophieRoot, appId) {
  if (isExternal(appId) && !isExternalReviewed(appDirFor(catasophieRoot, appId))) {
    return "needs-review";
  }
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

// Runs apps/<id>/up.sh or down.sh (or, for external apps that don't ship
// their own, drives podman-compose directly against their compose file -
// see apps/cli/scripts/lib/external.sh's external_up/external_down,
// mirrored here). Resolved relative to catasophieRoot. Rejects if the
// app isn't installed/reviewed or nothing runnable is found, so callers
// never need to shell-interpolate an arbitrary id.
async function runAppScript(catasophieRoot, appId, script) {
  if (!["up.sh", "down.sh"].includes(script)) {
    throw new Error(`refusing to run unexpected script: ${script}`);
  }
  const appDir = appDirFor(catasophieRoot, appId);

  if (isExternal(appId) && script === "up.sh" && !isExternalReviewed(appDir)) {
    throw new Error(
      `"${appId}" needs review before it can be started - run: ./apps/cli/scripts/review-external.sh ${appId.slice("external/".length)}`
    );
  }

  const scriptPath = path.join(appDir, script);
  if (fs.existsSync(scriptPath)) {
    const { stdout, stderr } = await execFileAsync("bash", [scriptPath], {
      cwd: appDir,
      timeout: 5 * 60 * 1000
    });
    return { stdout, stderr };
  }

  if (!isExternal(appId)) {
    throw new Error(`${script} not found for app "${appId}" - is it installed?`);
  }

  // External app with no up.sh/down.sh of its own - drive podman-compose
  // directly, same generic fallback as external_up/external_down.
  const composeFile = path.join(appDir, "docker-compose.yml");
  if (!fs.existsSync(composeFile)) {
    throw new Error(`no docker-compose.yml found for "${appId}"`);
  }
  const args =
    script === "up.sh"
      ? ["-f", composeFile, "up", "-d"]
      : ["-f", composeFile, "down"];
  const { stdout, stderr } = await execFileAsync("podman-compose", args, {
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
