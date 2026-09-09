/*
 * RESILIENCE HUB — LAN ADVERTISE HOST
 * ------------------------------------
 * Determines which host to use when building every app's URL, so links
 * shown by the dashboard work from other devices on the LAN, not just
 * from the machine the dashboard runs on ("localhost" would only ever
 * resolve to whichever device is viewing the page).
 *
 * Resolution order:
 *   1. DASHBOARD_ADVERTISE_HOST from .env, if set - explicit override,
 *      e.g. a static IP/hostname, or to disambiguate when this device
 *      has more than one active network interface.
 *   2. Auto-detect: the first non-internal IPv4 address found via
 *      os.networkInterfaces(). If more than one exists (e.g. Ethernet +
 *      this device's own WiFi hotspot both active), the rest are
 *      returned as `others` so the caller can log a hint about
 *      DASHBOARD_ADVERTISE_HOST.
 *   3. Fallback: "localhost", if no non-internal IPv4 address exists at
 *      all (e.g. no network connectivity).
 *
 * Resolved once per manifest scan (dashboard startup, or the "Rescan"
 * button/POST /api/rescan) - not per-request.
 */

const os = require("node:os");

function detectLanIPv4Addresses() {
  const interfaces = os.networkInterfaces();
  const addresses = [];
  for (const ifaceName of Object.keys(interfaces)) {
    for (const addr of interfaces[ifaceName] || []) {
      if (addr.family === "IPv4" && !addr.internal) {
        addresses.push({ iface: ifaceName, address: addr.address });
      }
    }
  }
  return addresses;
}

// Returns { host, source, others } where source is "override" | "auto-detected" | "fallback",
// and others is any additional candidate LAN addresses not chosen (empty unless ambiguous).
function getAdvertiseHost(env = process.env) {
  const override = (env.DASHBOARD_ADVERTISE_HOST || "").trim();
  if (override) {
    return { host: override, source: "override", others: [] };
  }

  const candidates = detectLanIPv4Addresses();
  if (candidates.length === 0) {
    return { host: "localhost", source: "fallback", others: [] };
  }

  const [chosen, ...rest] = candidates;
  return {
    host: chosen.address,
    source: "auto-detected",
    others: rest.map((c) => `${c.address} (${c.iface})`)
  };
}

module.exports = { getAdvertiseHost, detectLanIPv4Addresses };
