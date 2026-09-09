/*
 * RESILIENCE HUB — HOST INFO
 * --------------------------
 * Gathers host-level metrics for the dashboard's "Host" panel: IP,
 * connection state, CPU/RAM usage, and storage available. Split into
 * two update cadences, chosen to avoid adding latency to frequent
 * requests:
 *
 *   - Live, per-request (cheap, no delta/network needed): memory
 *     (os.totalmem/freemem, instant) and storage (`df -kP /`, ~10-20ms,
 *     same style as the podman calls in lib/status.js).
 *   - Background-sampled, independent of any request: CPU usage needs a
 *     delta between two os.cpus() snapshots to be meaningful (a single
 *     snapshot only gives cumulative time since boot), so a lightweight
 *     unref()'d timer re-samples it every DASHBOARD_STATUS_POLL_INTERVAL_SECONDS
 *     (same cadence server.js uses for the client's status poll - see
 *     startCpuSampler's caller) and callers just read the
 *     cached value - never blocking a request.
 *   - Tied to the same cadence as the manifest scan (dashboard startup,
 *     or the "Rescan" button - see server.js's reloadRegistry): the
 *     connection/gateway check, since network topology rarely changes
 *     and (unlike CPU/memory/storage) it involves a subprocess + a ping,
 *     which would be wasteful to redo on every 15s status poll.
 *
 * The gateway ping is strictly local (the LAN's own default gateway) -
 * never anything internet-bound, consistent with this repo's offline
 * philosophy (see AGENTS.md).
 */

const os = require("node:os");
const fs = require("node:fs");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");

const execFileAsync = promisify(execFile);

// --- CPU (background-sampled) -------------------------------------------

let lastCpuSample = null; // { idle, total } from the previous tick
let cachedCpuUsagePercent = null; // null until at least 2 samples taken
let cpuSamplerTimer = null;

function sumCpuTimes() {
  const cpus = os.cpus();
  let idle = 0;
  let total = 0;
  for (const cpu of cpus) {
    for (const key of Object.keys(cpu.times)) {
      total += cpu.times[key];
    }
    idle += cpu.times.idle;
  }
  return { idle, total, cores: cpus.length };
}

function sampleCpuTick() {
  const sample = sumCpuTimes();
  if (lastCpuSample) {
    const idleDelta = sample.idle - lastCpuSample.idle;
    const totalDelta = sample.total - lastCpuSample.total;
    if (totalDelta > 0) {
      cachedCpuUsagePercent = Math.max(0, Math.min(100, 100 * (1 - idleDelta / totalDelta)));
    }
  }
  lastCpuSample = sample;
}

// Starts the background CPU sampler (idempotent - safe to call more than
// once, e.g. across buildServer() calls in tests). The timer is
// unref()'d so it never keeps the process alive by itself. Callers
// should pass DASHBOARD_STATUS_POLL_INTERVAL_SECONDS * 1000 (see
// server.js) so this stays in sync with the client's status poll
// interval instead of ticking on its own separate schedule; the 2000ms
// default here only applies if called with no argument (e.g. tests).
function startCpuSampler(intervalMs = 2000) {
  if (cpuSamplerTimer) return;
  sampleCpuTick(); // establish a baseline immediately
  cpuSamplerTimer = setInterval(sampleCpuTick, intervalMs);
  cpuSamplerTimer.unref();
}

function getCpuUsage() {
  return {
    usagePercent: cachedCpuUsagePercent === null ? null : Math.round(cachedCpuUsagePercent * 10) / 10,
    cores: os.cpus().length
  };
}

// --- Memory (live) -------------------------------------------------------

function getMemoryInfo() {
  const total = os.totalmem();
  const free = os.freemem();
  const used = total - free;
  return {
    totalBytes: total,
    usedBytes: used,
    freeBytes: free,
    usedPercent: total > 0 ? Math.round((used / total) * 1000) / 10 : 0
  };
}

// --- Storage (live, root filesystem) -------------------------------------

async function getStorageInfo(targetPath = "/") {
  try {
    const { stdout } = await execFileAsync("df", ["-kP", targetPath], { timeout: 2000 });
    const lines = stdout.trim().split("\n");
    const fields = lines[lines.length - 1].trim().split(/\s+/);
    // Filesystem 1024-blocks Used Available Capacity Mounted-on
    const totalBytes = Number(fields[1]) * 1024;
    const usedBytes = Number(fields[2]) * 1024;
    const availableBytes = Number(fields[3]) * 1024;
    return {
      path: targetPath,
      totalBytes,
      usedBytes,
      availableBytes,
      usedPercent: totalBytes > 0 ? Math.round((usedBytes / totalBytes) * 1000) / 10 : 0
    };
  } catch (err) {
    return { path: targetPath, error: String(err.message || err) };
  }
}

// --- Connection state (scan-cadence: startup + Rescan) -------------------

// Default gateway, Linux: read /proc/net/route directly (no subprocess) -
// the default route has destination 00000000, gateway is a
// little-endian hex IP in the 3rd field.
function getDefaultGatewayLinux() {
  try {
    const contents = fs.readFileSync("/proc/net/route", "utf8");
    const lines = contents.trim().split("\n").slice(1);
    for (const line of lines) {
      const fields = line.trim().split(/\s+/);
      const [, destination, gateway] = fields;
      if (destination === "00000000" && gateway && gateway !== "00000000") {
        const bytes = [0, 2, 4, 6].map((i) => parseInt(gateway.slice(i, i + 2), 16));
        return bytes.reverse().join(".");
      }
    }
  } catch (err) {
    // fall through to null
  }
  return null;
}

// Default gateway, macOS/BSD: parse `route -n get default`.
async function getDefaultGatewayDarwin() {
  try {
    const { stdout } = await execFileAsync("route", ["-n", "get", "default"], { timeout: 1500 });
    const match = stdout.match(/gateway:\s*(\S+)/);
    return match ? match[1] : null;
  } catch (err) {
    return null;
  }
}

async function getDefaultGateway() {
  if (process.platform === "linux") {
    return getDefaultGatewayLinux();
  }
  if (process.platform === "darwin") {
    return getDefaultGatewayDarwin();
  }
  return null;
}

// Pings the gateway once, local-only (never anything internet-bound).
// Platform-specific timeout flag (-W seconds on Linux, -t seconds on
// macOS/BSD), plus a hard subprocess timeout as a safety net regardless
// of flag quirks on any given platform/ping implementation.
async function pingOnce(ip) {
  const args =
    process.platform === "darwin" ? ["-c", "1", "-t", "1", ip] : ["-c", "1", "-W", "1", ip];
  try {
    await execFileAsync("ping", args, { timeout: 1500 });
    return true;
  } catch (err) {
    return false;
  }
}

// Returns { state, label, interface, gateway } - state is one of
// "isolated" (no LAN IP at all), "link-up" (has an IP but no gateway
// found, or it didn't respond), or "connected" (has an IP and the
// gateway responded to a local ping).
async function getConnectionInfo(advertiseHostResult) {
  const { source, others } = advertiseHostResult;
  if (source === "fallback") {
    return { state: "isolated", label: "No network detected", gateway: null, others };
  }

  const gateway = await getDefaultGateway();
  if (!gateway) {
    return { state: "link-up", label: "Link up (no gateway found)", gateway: null, others };
  }

  const reachable = await pingOnce(gateway);
  if (reachable) {
    return { state: "connected", label: "Connected", gateway, others };
  }
  return { state: "link-up", label: "Link up (gateway unreachable)", gateway, others };
}

module.exports = {
  startCpuSampler,
  getCpuUsage,
  getMemoryInfo,
  getStorageInfo,
  getConnectionInfo
};
