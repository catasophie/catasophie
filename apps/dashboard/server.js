"use strict";

const path = require("node:path");
const fs = require("node:fs");
const Fastify = require("fastify");
const fastifyView = require("@fastify/view");
const fastifyStatic = require("@fastify/static");
const fastifyFormbody = require("@fastify/formbody");
const Handlebars = require("handlebars");

Handlebars.registerHelper("formatBytes", (bytes) => {
  if (typeof bytes !== "number" || Number.isNaN(bytes)) return "-";
  const units = ["B", "KiB", "MiB", "GiB", "TiB"];
  let value = bytes;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  return `${value.toFixed(unitIndex === 0 ? 0 : 1)} ${units[unitIndex]}`;
});

const { scanApps, CATASOPHIE_ROOT } = require("./lib/registry");
const { getAdvertiseHost } = require("./lib/network");
const { statusesFor, startApp, stopApp } = require("./lib/status");
const hostinfo = require("./lib/hostinfo");
const hotspot = require("./lib/hotspot");

// Load .env (simple KEY=VALUE parser, no dependency needed) so
// DASHBOARD_PORT etc. are available without requiring dotenv.
function loadEnvFileToObject(envPath) {
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

function loadEnvFile(envPath) {
  const values = loadEnvFileToObject(envPath);
  for (const [key, value] of Object.entries(values)) {
    if (!(key in process.env)) process.env[key] = value;
  }
}

// Snapshot the truly-exported environment (before loadEnvFile mutates
// process.env below) so a later rescan can tell "explicitly exported in
// the shell that started us" (should keep overriding) apart from
// "loaded from .env at boot" (should be re-read fresh on each rescan,
// so editing .env's DASHBOARD_ADVERTISE_HOST etc. doesn't need a full
// restart to take effect).
const ORIGINAL_ENV = { ...process.env };

loadEnvFile(path.join(__dirname, ".env"));

const PORT = Number(process.env.DASHBOARD_PORT || 8000);
const HOST = process.env.DASHBOARD_HOST || "0.0.0.0";
const SYSTEM_NAME = process.env.DASHBOARD_SYSTEM_NAME || "Resilience Hub";
const LOCATION = process.env.DASHBOARD_LOCATION || "";
const STATUS_POLL_INTERVAL_SECONDS = Number(process.env.DASHBOARD_STATUS_POLL_INTERVAL_SECONDS || 15);

function groupByCategory(apps) {
  const order = [];
  const byCategory = new Map();
  for (const app of apps) {
    const cat = app.category || "Other";
    if (!byCategory.has(cat)) {
      byCategory.set(cat, []);
      order.push(cat);
    }
    byCategory.get(cat).push(app);
  }
  return order.map((cat) => ({ name: cat, apps: byCategory.get(cat) }));
}

function buildAppsForView(apps, statuses) {
  return apps.map((app) => ({
    ...app,
    status: statuses[app.id] || "unknown",
    isRunning: statuses[app.id] === "running",
    isStopped: statuses[app.id] === "stopped",
    isNotInstalled: statuses[app.id] === "not-installed",
    isNeedsReview: statuses[app.id] === "needs-review"
  }));
}

async function buildServer() {
  const fastify = Fastify({ logger: true });

  // Reuse DASHBOARD_STATUS_POLL_INTERVAL_SECONDS for the CPU background
  // sampler too, instead of a separate hardcoded interval - one poll
  // cadence for all "how healthy is this host right now" metrics.
  hostinfo.startCpuSampler(STATUS_POLL_INTERVAL_SECONDS * 1000);

  // Manifest scan is cached and only re-run at startup or via
  // POST /api/rescan (triggered by the "Rescan" button) - not on every
  // request/poll, per docs/ADDING_AN_APP.md's manifest.json contract.
  // The connection/gateway check is cached on the same cadence (see
  // lib/hostinfo.js) since it involves a subprocess + a ping.
  let registry = { apps: [], errors: [] };
  let connectionInfo = { state: "link-up", label: "Checking…", gateway: null, others: [] };
  let advertiseHost = "localhost";

  async function reloadRegistry() {
    // Re-read .env fresh (not just what was loaded at process startup) so
    // an edit to DASHBOARD_ADVERTISE_HOST takes effect on the next scan
    // without needing a full dashboard restart - a truly shell-exported
    // var (ORIGINAL_ENV, captured before loadEnvFile ran) still wins.
    const freshEnv = { ...loadEnvFileToObject(path.join(__dirname, ".env")), ...ORIGINAL_ENV };
    const advertiseHostResult = getAdvertiseHost(freshEnv);
    const { host, source, others } = advertiseHostResult;
    advertiseHost = host;
    if (others.length > 0) {
      fastify.log.warn(
        `multiple LAN addresses found, using ${host} - set DASHBOARD_ADVERTISE_HOST to override (other candidates: ${others.join(", ")})`
      );
    }
    if (source === "fallback") {
      fastify.log.warn("no LAN network interface found - advertising \"localhost\", which only works from this device. Set DASHBOARD_ADVERTISE_HOST if this is wrong.");
    }
    registry = scanApps(CATASOPHIE_ROOT, host);
    for (const err of registry.errors) {
      fastify.log.warn(`skipping apps/${err.id}/manifest.json: ${err.reason}`);
    }
    fastify.log.info(`registry loaded (advertising ${host}, ${source}): ${registry.apps.map((a) => a.id).join(", ") || "(no apps found)"}`);

    connectionInfo = await hostinfo.getConnectionInfo(advertiseHostResult);
    fastify.log.info(`connection state: ${connectionInfo.state} (${connectionInfo.label})`);

    return registry;
  }

  async function getHostSnapshot() {
    const storage = await hostinfo.getStorageInfo("/");
    return {
      ip: advertiseHost,
      connection: connectionInfo,
      cpu: hostinfo.getCpuUsage(),
      memory: hostinfo.getMemoryInfo(),
      storage,
      hotspot: await hotspot.getHotspotStatus(CATASOPHIE_ROOT)
    };
  }

  await reloadRegistry();

  await fastify.register(fastifyFormbody);

  await fastify.register(fastifyStatic, {
    root: path.join(__dirname, "public"),
    prefix: "/public/"
  });

  await fastify.register(fastifyView, {
    engine: { handlebars: Handlebars },
    root: path.join(__dirname, "views"),
    layout: "layout.hbs",
    viewExt: "hbs",
    options: {
      partials: {
        card: "partials/card.hbs"
      }
    }
  });

  fastify.get("/", async (request, reply) => {
    const statuses = await statusesFor(CATASOPHIE_ROOT, registry.apps);
    const apps = buildAppsForView(registry.apps, statuses);
    const online = apps.filter((a) => a.isRunning).length;
    const categories = groupByCategory(apps);
    const host = await getHostSnapshot();
    return reply.view("index.hbs", {
      systemName: SYSTEM_NAME,
      location: LOCATION,
      statusPollIntervalSeconds: STATUS_POLL_INTERVAL_SECONDS,
      categories,
      online,
      total: apps.length,
      host
    });
  });

  fastify.get("/api/status", async (request, reply) => {
    const statuses = await statusesFor(CATASOPHIE_ROOT, registry.apps);
    const apps = buildAppsForView(registry.apps, statuses);
    const host = await getHostSnapshot();
    return reply.send({
      generatedAt: new Date().toISOString(),
      host,
      apps: apps.map((a) => ({
        id: a.id,
        status: a.status,
        isRunning: a.isRunning,
        isStopped: a.isStopped,
        isNotInstalled: a.isNotInstalled,
        isNeedsReview: a.isNeedsReview
      }))
    });
  });

  // Re-scans apps/<id>/manifest.json (picking up newly added/removed apps
  // and any .env port changes) and returns the same shape as
  // GET /api/status. Called by the "Rescan" button.
  fastify.post("/api/rescan", async (request, reply) => {
    await reloadRegistry();
    const statuses = await statusesFor(CATASOPHIE_ROOT, registry.apps);
    const apps = buildAppsForView(registry.apps, statuses);
    const host = await getHostSnapshot();
    return reply.send({
      generatedAt: new Date().toISOString(),
      errors: registry.errors,
      host,
      apps: apps.map((a) => ({
        id: a.id,
        status: a.status,
        isRunning: a.isRunning,
        isStopped: a.isStopped,
        isNotInstalled: a.isNotInstalled,
        isNeedsReview: a.isNeedsReview
      }))
    });
  });

  fastify.post("/apps/:id/start", async (request, reply) => {
    const { id } = request.params;
    const app = registry.apps.find((a) => a.id === id);
    if (!app) {
      return reply.code(404).send({ ok: false, error: "unknown app" });
    }
    try {
      await startApp(CATASOPHIE_ROOT, id);
      const status = await statusesFor(CATASOPHIE_ROOT, [app]);
      return reply.send({ ok: true, status: status[id] });
    } catch (err) {
      request.log.error(err);
      return reply.code(500).send({ ok: false, error: String(err.message || err) });
    }
  });

  fastify.post("/apps/:id/stop", async (request, reply) => {
    const { id } = request.params;
    const app = registry.apps.find((a) => a.id === id);
    if (!app) {
      return reply.code(404).send({ ok: false, error: "unknown app" });
    }
    try {
      await stopApp(CATASOPHIE_ROOT, id);
      const status = await statusesFor(CATASOPHIE_ROOT, [app]);
      return reply.send({ ok: true, status: status[id] });
    } catch (err) {
      request.log.error(err);
      return reply.code(500).send({ ok: false, error: String(err.message || err) });
    }
  });

  // Turns the host's WiFi hotspot on/off (see apps/cli/scripts/hotspot-up.sh
  // and hotspot-down.sh). "up" is rejected if the hotspot hasn't been
  // configured yet via `make hotspot-up` at least once (see lib/hotspot.js).
  fastify.post("/api/hotspot/:action", async (request, reply) => {
    const { action } = request.params;
    if (!["up", "down"].includes(action)) {
      return reply.code(404).send({ ok: false, error: "unknown hotspot action" });
    }
    try {
      await hotspot.toggleHotspot(CATASOPHIE_ROOT, action);
      const status = await hotspot.getHotspotStatus(CATASOPHIE_ROOT);
      return reply.send({ ok: true, hotspot: status });
    } catch (err) {
      request.log.error(err);
      return reply.code(500).send({ ok: false, error: String(err.message || err) });
    }
  });

  return fastify;
}

async function main() {
  const fastify = await buildServer();
  try {
    await fastify.listen({ port: PORT, host: HOST });
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}

module.exports = { buildServer };
