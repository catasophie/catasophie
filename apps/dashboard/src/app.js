/*
 * RESILIENCE HUB — DASHBOARD LOGIC
 * No external dependencies. No network calls except to your own
 * local sub-apps (for status checks). Safe to run fully offline.
 */

(function () {
  "use strict";

  const ICONS = {
    radio: '<path d="M4 14v6a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-6" /><path d="M12 14a4 4 0 0 0 4-4V6a4 4 0 1 0-8 0v4a4 4 0 0 0 4 4Z" /><path d="M8 22h8" /><path d="M2 14 6 6" /><path d="M22 14 18 6" />',
    map: '<path d="M9 3 3 5.5v15L9 18l6 3 6-2.5v-15L15 6l-6-3Z" /><path d="M9 3v15" /><path d="M15 6v15" />',
    medkit: '<rect x="3" y="8" width="18" height="12" rx="2" /><path d="M9 8V6a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2" /><path d="M12 12v4" /><path d="M10 14h4" />',
    bolt: '<path d="M13 2 4 14h6l-1 8 9-12h-6l1-8Z" />',
    droplet: '<path d="M12 2s7 8.5 7 13a7 7 0 0 1-14 0c0-4.5 7-13 7-13Z" />',
    book: '<path d="M4 4.5A2.5 2.5 0 0 1 6.5 2H20v16H6.5A2.5 2.5 0 0 0 4 20.5v-16Z" /><path d="M20 18H6.5a2.5 2.5 0 0 0 0 5H20" />',
    shield: '<path d="M12 2 4 5v6c0 5 3.4 8.9 8 11 4.6-2.1 8-6 8-11V5l-8-3Z" />',
    tools: '<path d="M14.7 6.3a4 4 0 0 0-5.4 5.4L2 19l3 3 7.3-7.3a4 4 0 0 0 5.4-5.4l-2.8 2.8-2-2 2.8-2.8Z" />',
    camera: '<path d="M4 8h3l1.5-2h7L17 8h3a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1Z" /><circle cx="12" cy="14" r="3.5" />',
    server: '<rect x="3" y="4" width="18" height="6" rx="1" /><rect x="3" y="14" width="18" height="6" rx="1" /><circle cx="7" cy="7" r="0.8" fill="currentColor" stroke="none" /><circle cx="7" cy="17" r="0.8" fill="currentColor" stroke="none" />'
  };

  function iconSvg(key) {
    const paths = ICONS[key] || ICONS.server;
    return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">${paths}</svg>`;
  }

  const state = {
    apps: APPS_CONFIG.apps.map((a) => ({ ...a, status: "checking" })),
    filterCategory: "all",
    query: ""
  };

  const el = {
    grid: document.getElementById("grid"),
    clock: document.getElementById("clock"),
    summary: document.getElementById("summary"),
    search: document.getElementById("search"),
    chips: document.getElementById("chips"),
    lastScan: document.getElementById("last-scan"),
    systemName: document.getElementById("system-name"),
    location: document.getElementById("location")
  };

  function appUrl(app) {
    return `${app.protocol}://${app.host}:${app.port}${app.path || "/"}`;
  }

  function buildUrl(app) {
    return appUrl(app);
  }

  // --- Status checking -----------------------------------------------
  // We can't reliably read HTTP status codes cross-origin without CORS
  // support from the sub-app, so this uses a best-effort reachability
  // check: if a request to the host:port resolves or errors quickly
  // in a way that indicates the port is open, we call it online.
  function checkApp(app) {
    return new Promise((resolve) => {
      const controller = new AbortController();
      const timeout = setTimeout(() => {
        controller.abort();
        resolve({ id: app.id, status: "offline" });
      }, APPS_CONFIG.statusCheckTimeoutMs || 2500);

      fetch(buildUrl(app), { mode: "no-cors", signal: controller.signal, cache: "no-store" })
        .then(() => {
          clearTimeout(timeout);
          resolve({ id: app.id, status: "online" });
        })
        .catch(() => {
          clearTimeout(timeout);
          resolve({ id: app.id, status: "offline" });
        });
    });
  }

  async function refreshStatuses() {
    const results = await Promise.all(state.apps.map(checkApp));
    const byId = Object.fromEntries(results.map((r) => [r.id, r.status]));
    state.apps.forEach((a) => (a.status = byId[a.id] || "offline"));
    render();
    if (el.lastScan) {
      const now = new Date();
      el.lastScan.textContent = `Last scan ${now.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" })}`;
    }
  }

  // --- Rendering -------------------------------------------------------
  function categories() {
    const set = new Set(state.apps.map((a) => a.category || "Other"));
    return Array.from(set);
  }

  function renderChips() {
    const cats = ["all", ...categories()];
    el.chips.innerHTML = cats
      .map((c) => {
        const label = c === "all" ? "All systems" : c;
        const active = state.filterCategory === c ? "chip active" : "chip";
        return `<button class="${active}" data-cat="${escapeAttr(c)}">${escapeHtml(label)}</button>`;
      })
      .join("");
  }

  function matchesFilter(app) {
    const catOk = state.filterCategory === "all" || app.category === state.filterCategory;
    const q = state.query.trim().toLowerCase();
    const qOk =
      !q ||
      app.name.toLowerCase().includes(q) ||
      (app.description || "").toLowerCase().includes(q) ||
      (app.category || "").toLowerCase().includes(q);
    return catOk && qOk;
  }

  function render() {
    const filtered = state.apps.filter(matchesFilter);
    const grouped = {};
    filtered.forEach((a) => {
      const cat = a.category || "Other";
      grouped[cat] = grouped[cat] || [];
      grouped[cat].push(a);
    });

    const cats = Object.keys(grouped);
    if (cats.length === 0) {
      el.grid.innerHTML = `<div class="empty">No systems match "${escapeHtml(state.query)}". Check the spelling, or clear the filter to see everything.</div>`;
    } else {
      el.grid.innerHTML = cats
        .map((cat) => {
          const cards = grouped[cat]
            .map((app) => cardHtml(app))
            .join("");
          return `<section class="category"><h2>${escapeHtml(cat)}</h2><div class="cards">${cards}</div></section>`;
        })
        .join("");
    }

    const online = state.apps.filter((a) => a.status === "online").length;
    const total = state.apps.length;
    el.summary.innerHTML = `<span class="dot ${online === total ? "dot-online" : online === 0 ? "dot-offline" : "dot-partial"}"></span>${online} / ${total} systems online`;

    renderChips();
  }

  function cardHtml(app) {
    const statusLabel = app.status === "online" ? "Online" : app.status === "checking" ? "Checking" : "Offline";
    const statusClass = `status-${app.status}`;
    return `
      <a class="card ${app.status === "offline" ? "card-offline" : ""}" href="${escapeAttr(buildUrl(app))}" target="_blank" rel="noopener noreferrer" data-id="${escapeAttr(app.id)}">
        <div class="card-top">
          <span class="card-icon">${iconSvg(app.icon)}</span>
          <span class="status ${statusClass}"><span class="status-dot"></span>${statusLabel}</span>
        </div>
        <h3>${escapeHtml(app.name)}</h3>
        <p>${escapeHtml(app.description || "")}</p>
        <div class="card-meta">${escapeHtml(app.host)}:${app.port}</div>
      </a>`;
  }

  function escapeHtml(str) {
    return String(str).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  }
  function escapeAttr(str) {
    return escapeHtml(str);
  }

  // --- Clock -------------------------------------------------------------
  function tickClock() {
    const now = new Date();
    el.clock.textContent = now.toLocaleString([], {
      weekday: "short",
      year: "numeric",
      month: "short",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit"
    });
  }

  // --- Init ----------------------------------------------------------------
  function init() {
    el.systemName.textContent = APPS_CONFIG.systemName || "Resilience Hub";
    if (APPS_CONFIG.location) {
      el.location.textContent = APPS_CONFIG.location;
      el.location.hidden = false;
    }

    el.search.addEventListener("input", (e) => {
      state.query = e.target.value;
      render();
    });

    el.chips.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-cat]");
      if (!btn) return;
      state.filterCategory = btn.getAttribute("data-cat");
      render();
    });

    document.getElementById("refresh-btn").addEventListener("click", () => {
      state.apps.forEach((a) => (a.status = "checking"));
      render();
      refreshStatuses();
    });

    render();
    tickClock();
    setInterval(tickClock, 1000 * 30);

    refreshStatuses();
    const intervalMs = (APPS_CONFIG.statusCheckIntervalSeconds || 15) * 1000;
    setInterval(refreshStatuses, intervalMs);
  }

  document.addEventListener("DOMContentLoaded", init);
})();
