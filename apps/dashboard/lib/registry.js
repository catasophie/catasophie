/*
 * RESILIENCE HUB — APP REGISTRY (directory scan)
 * -----------------------------------------------
 * Instead of a hand-maintained list, the dashboard discovers apps by
 * scanning apps/<id>/manifest.json - every app that wants to appear on the
 * dashboard ships one (see docs/ADDING_AN_APP.md). No manifest = the app
 * simply doesn't show up (this is how apps/_template, apps/cli, and
 * apps/dashboard itself are naturally excluded, no hardcoded skip-list
 * needed).
 *
 * Manifest schema (apps/<id>/manifest.json, or apps/external/<id>/manifest.json
 * for third-party apps - see apps/external/README.md and docs/EXTERNAL_APPS.md):
 *   {
 *     "name": "Offline Maps",                 required
 *     "description": "One short sentence.",   required
 *     "category": "Navigation",               required
 *     "icon": "map",                           required (see public/app.js ICONS)
 *     "protocol": "http",                      optional, default "http"
 *     "path": "/",                             optional, default "/"
 *     "port": { "envVar": "MAPS_WEB_PORT", "default": 3010 },   required
 *     "type": "external",                      optional, third-party apps only
 *     "source": "https://github.com/..."       optional, third-party apps only
 *   }
 *
 * There's no per-app "host" field - every app runs on the same device as
 * the dashboard, so the host used to build each app's URL is a single
 * dashboard-wide value (see lib/network.js's getAdvertiseHost, passed
 * into scanApps below) rather than something each manifest repeats.
 *
 * The actual port shown/used is read live from that app's own .env at
 * scan time (falling back to port.default if .env or the var is
 * missing/unset) - the app's .env stays the single source of truth for
 * its port, matching how every other tool in this repo resolves it.
 * Scanning happens once at dashboard startup and whenever the "Rescan"
 * button (or POST /api/rescan) is used - not on every request/poll.
 */

const fs = require("node:fs");
const path = require("node:path");

const CATASOPHIE_ROOT = path.resolve(__dirname, "..", "..", "..");

const REQUIRED_FIELDS = ["name", "description", "category", "icon", "port"];

function parseEnvFile(envPath) {
  const values = {};
  if (!fs.existsSync(envPath)) return values;
  for (const line of fs.readFileSync(envPath, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    const value = trimmed.slice(eq + 1).trim();
    values[key] = value;
  }
  return values;
}

function resolvePort(appDir, portSpec) {
  const envValues = parseEnvFile(path.join(appDir, ".env"));
  const fromEnv = portSpec.envVar ? envValues[portSpec.envVar] : undefined;
  if (fromEnv && /^\d+$/.test(fromEnv)) {
    return Number(fromEnv);
  }
  return portSpec.default;
}

function validateManifest(manifest) {
  const missing = REQUIRED_FIELDS.filter((f) => manifest[f] === undefined || manifest[f] === null || manifest[f] === "");
  if (missing.length > 0) {
    return `missing required field(s): ${missing.join(", ")}`;
  }
  if (typeof manifest.port !== "object" || !manifest.port.envVar || manifest.port.default === undefined) {
    return 'invalid "port" field - expected { "envVar": "...", "default": <number> }';
  }
  if (typeof manifest.port.default !== "number") {
    return '"port.default" must be a number';
  }
  return null;
}

// Scans apps/<id>/manifest.json (and apps/external/<id>/manifest.json,
// for third-party apps the user manually cloned in - see
// apps/external/README.md and docs/EXTERNAL_APPS.md) and returns
// { apps, errors }.
// apps: array of fully-resolved app entries (id, name, description,
//       category, icon, protocol, path, port, url, external).
//       External apps get id "external/<dirname>" and external: true,
//       so the rest of the dashboard/toolchain can tell them apart from
//       first-party apps without a separate list.
// errors: array of { id, reason } for present-but-invalid manifests
//         (missing manifest.json is not an error - it's how non-dashboard
//         directories like _template/cli/dashboard are excluded).
// advertiseHost: the host to use for every app's url (see lib/network.js) -
//         all apps run on the same device as the dashboard, so this is a
//         single value shared across every entry, not per-manifest.
function scanApps(catasophieRoot = CATASOPHIE_ROOT, advertiseHost = "localhost") {
  const appsDir = path.join(catasophieRoot, "apps");
  const apps = [];
  const errors = [];

  function scanDir(dir, idPrefix) {
    let entries = [];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch (err) {
      if (idPrefix === "") {
        errors.push({ id: "apps/", reason: String(err.message || err) });
      }
      return;
    }

    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      const name = entry.name;
      if (idPrefix === "" && name === "external") continue; // scanned separately below
      const id = idPrefix + name;
      const appDir = path.join(dir, name);
      const manifestPath = path.join(appDir, "manifest.json");
      if (!fs.existsSync(manifestPath)) continue; // opt-in: no manifest, no dashboard entry

      let manifest;
      try {
        manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
      } catch (err) {
        errors.push({ id, reason: `invalid JSON in manifest.json: ${err.message}` });
        continue;
      }

      const validationError = validateManifest(manifest);
      if (validationError) {
        errors.push({ id, reason: validationError });
        continue;
      }

      const protocol = manifest.protocol || "http";
      const appPath = manifest.path || "/";
      const port = resolvePort(appDir, manifest.port);
      const external = idPrefix !== "";

      apps.push({
        id,
        name: manifest.name,
        description: manifest.description,
        category: manifest.category,
        icon: manifest.icon,
        protocol,
        host: advertiseHost,
        path: appPath,
        port,
        url: `${protocol}://${advertiseHost}:${port}${appPath}`,
        external,
        source: external ? manifest.source || null : undefined
      });
    }
  }

  scanDir(appsDir, "");
  scanDir(path.join(appsDir, "external"), "external/");

  apps.sort((a, b) => a.name.localeCompare(b.name));
  return { apps, errors };
}

module.exports = { scanApps, CATASOPHIE_ROOT };
