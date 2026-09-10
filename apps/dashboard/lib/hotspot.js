/*
 * Hotspot status + toggle helpers, wired to the CLI scripts in
 * apps/cli/scripts/hotspot-up.sh / hotspot-down.sh (see AGENTS.md and
 * that script's own header comment).
 *
 * Design: the dashboard can only *toggle* an already-configured
 * hotspot - initial setup (choosing SSID/password/WiFi interface) stays
 * a one-time CLI step (`make hotspot-up` over SSH). Two reasons:
 *   1. Picking a WiFi interface when there's more than one is an
 *      interactive prompt in the script; the dashboard must never risk
 *      blocking on stdin.
 *   2. hotspot-up.sh always persists all 4 keys (HOTSPOT_IFACE,
 *      HOTSPOT_SSID, HOTSPOT_PASSWORD, HOTSPOT_IP_CIDR) to .hotspot.env
 *      on any completed run - even for an open/no-password network - so
 *      "all 4 keys present" reliably means "safe to re-run
 *      non-interactively" (prompt_if_unset/the password check both read
 *      straight from the file instead of prompting).
 */

const fs = require("node:fs");
const path = require("node:path");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");

const execFileAsync = promisify(execFile);

const CONN_NAME = "catasophie-hotspot";
const REQUIRED_KEYS = ["HOTSPOT_IFACE", "HOTSPOT_SSID", "HOTSPOT_PASSWORD", "HOTSPOT_IP_CIDR"];

function hotspotEnvFile(catasophieRoot) {
  return path.join(catasophieRoot, "apps", "cli", "scripts", ".hotspot.env");
}

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

async function isNmcliAvailable() {
  try {
    await execFileAsync("nmcli", ["--version"], { timeout: 2000 });
    return true;
  } catch (err) {
    return false;
  }
}

// Returns { supported, configured, active, ssid, ip }.
async function getHotspotStatus(catasophieRoot) {
  const supported = await isNmcliAvailable();
  if (!supported) {
    return { supported: false, configured: false, active: false, ssid: null, ip: null };
  }

  const values = parseEnvFile(hotspotEnvFile(catasophieRoot));
  const configured = REQUIRED_KEYS.every((k) => values[k] !== undefined);
  if (!configured) {
    return { supported: true, configured: false, active: false, ssid: null, ip: null };
  }

  let active = false;
  try {
    const { stdout } = await execFileAsync("nmcli", ["-t", "-f", "NAME", "connection", "show", "--active"], {
      timeout: 5000
    });
    active = stdout
      .split("\n")
      .map((l) => l.trim())
      .filter(Boolean)
      .includes(CONN_NAME);
  } catch (err) {
    // Treat as inactive/unknown rather than failing the whole status call.
    active = false;
  }

  return {
    supported: true,
    configured: true,
    active,
    ssid: values.HOTSPOT_SSID || null,
    ip: (values.HOTSPOT_IP_CIDR || "").split("/")[0] || null
  };
}

// Runs apps/cli/scripts/hotspot-up.sh or hotspot-down.sh. Rejects if
// trying to turn on a not-yet-configured hotspot, to avoid ever
// blocking on the script's first-run interactive prompts.
async function toggleHotspot(catasophieRoot, action) {
  if (!["up", "down"].includes(action)) {
    throw new Error(`unknown hotspot action: ${action}`);
  }

  if (action === "up") {
    const status = await getHotspotStatus(catasophieRoot);
    if (!status.supported) {
      throw new Error("hotspot isn't supported on this host (nmcli/NetworkManager not found)");
    }
    if (!status.configured) {
      throw new Error("hotspot isn't configured yet - run `make hotspot-up` once over SSH first");
    }
  }

  const scriptPath = path.join(catasophieRoot, "apps", "cli", "scripts", `hotspot-${action}.sh`);
  if (!fs.existsSync(scriptPath)) {
    throw new Error(`hotspot-${action}.sh not found`);
  }

  const { stdout, stderr } = await execFileAsync("bash", [scriptPath], {
    cwd: catasophieRoot,
    timeout: 30 * 1000
  });
  return { stdout, stderr };
}

module.exports = {
  getHotspotStatus,
  toggleHotspot
};
