/*
 * RESILIENCE HUB — DASHBOARD CLIENT LOGIC
 * The page itself is server-rendered (Fastify + Handlebars); this file
 * only handles: icon rendering, search/category filtering of the
 * already-rendered cards, periodic status polling via /api/status, and
 * wiring up the Start/Stop buttons to POST /apps/:id/start|stop.
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

  function renderIcons() {
    document.querySelectorAll(".card-icon[data-icon]").forEach((el) => {
      el.innerHTML = iconSvg(el.getAttribute("data-icon"));
    });
  }

  // --- Search / category filter (operates on server-rendered DOM) -----
  const state = { filterCategory: "all", query: "" };

  function applyFilter() {
    const q = state.query.trim().toLowerCase();
    let anyVisibleInCategory = {};

    document.querySelectorAll(".category").forEach((section) => {
      const cat = section.getAttribute("data-category");
      let visibleCount = 0;
      section.querySelectorAll(".card").forEach((card) => {
        const name = (card.querySelector("h3")?.textContent || "").toLowerCase();
        const desc = (card.querySelector("p")?.textContent || "").toLowerCase();
        const catOk = state.filterCategory === "all" || state.filterCategory === cat;
        const qOk = !q || name.includes(q) || desc.includes(q) || cat.toLowerCase().includes(q);
        const visible = catOk && qOk;
        card.style.display = visible ? "" : "none";
        if (visible) visibleCount++;
      });
      section.style.display = visibleCount > 0 ? "" : "none";
      anyVisibleInCategory[cat] = visibleCount > 0;
    });

    const grid = document.getElementById("grid");
    const anyVisible = Object.values(anyVisibleInCategory).some(Boolean);
    let emptyEl = grid.querySelector(".empty-filtered");
    if (!anyVisible) {
      if (!emptyEl) {
        emptyEl = document.createElement("div");
        emptyEl.className = "empty empty-filtered";
        grid.appendChild(emptyEl);
      }
      emptyEl.textContent = `No systems match "${state.query}". Check the spelling, or clear the filter to see everything.`;
    } else if (emptyEl) {
      emptyEl.remove();
    }
  }

  function initFilters() {
    const search = document.getElementById("search");
    const chips = document.getElementById("chips");
    if (search) {
      search.addEventListener("input", (e) => {
        state.query = e.target.value;
        applyFilter();
      });
    }
    if (chips) {
      chips.addEventListener("click", (e) => {
        const btn = e.target.closest("[data-cat]");
        if (!btn) return;
        state.filterCategory = btn.getAttribute("data-cat");
        chips.querySelectorAll(".chip").forEach((c) => c.classList.toggle("active", c === btn));
        applyFilter();
      });
    }
  }

  // --- Status polling ---------------------------------------------------
  function setCardStatus(id, status) {
    const statusEl = document.querySelector(`.status[data-status-for="${id}"]`);
    const card = document.querySelector(`.card[data-id="${id}"]`);
    if (!statusEl || !card) return;

    statusEl.className = `status status-${status}`;
    const label = statusEl.querySelector(".status-label");
    if (label) {
      label.textContent =
        status === "running" ? "Online" : status === "pending" ? "Working…" : status === "not-installed" ? "Not installed" : "Offline";
    }

    card.classList.toggle("card-offline", status === "stopped" || status === "unknown");
    card.classList.toggle("card-not-installed", status === "not-installed");

    const startBtn = card.querySelector(".start-btn");
    const stopBtn = card.querySelector(".stop-btn");
    if (startBtn) startBtn.disabled = status === "running" || status === "pending";
    if (stopBtn) stopBtn.disabled = status !== "running" || status === "pending";
  }

  function updateSummary(apps) {
    const online = apps.filter((a) => a.isRunning).length;
    const total = apps.length;
    const dot = document.getElementById("summary-dot");
    const text = document.getElementById("summary-text");
    if (dot) {
      dot.className = `dot ${online === total ? "dot-online" : online === 0 ? "dot-offline" : "dot-partial"}`;
    }
    if (text) text.textContent = `${online} / ${total} systems online`;
  }

  // --- Host panel ---------------------------------------------------------
  function formatBytes(bytes) {
    if (typeof bytes !== "number" || Number.isNaN(bytes)) return "-";
    const units = ["B", "KiB", "MiB", "GiB", "TiB"];
    let value = bytes;
    let unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    return `${value.toFixed(unitIndex === 0 ? 0 : 1)} ${units[unitIndex]}`;
  }

  function updateHostPanel(host) {
    if (!host) return;

    const ipEl = document.getElementById("host-ip");
    if (ipEl) ipEl.textContent = host.ip;

    const connEl = document.getElementById("host-connection");
    const connLabelEl = document.getElementById("host-connection-label");
    if (connEl && host.connection) {
      connEl.className = `status status-conn-${host.connection.state}`;
      if (connLabelEl) connLabelEl.textContent = host.connection.label;
    }

    const cpuBar = document.getElementById("host-cpu-bar");
    const cpuText = document.getElementById("host-cpu-text");
    if (host.cpu && host.cpu.usagePercent !== null && host.cpu.usagePercent !== undefined) {
      if (cpuBar) cpuBar.style.width = `${host.cpu.usagePercent}%`;
      if (cpuText) cpuText.textContent = `${host.cpu.usagePercent}% of ${host.cpu.cores} cores`;
    } else if (cpuText) {
      cpuText.textContent = "measuring…";
    }

    const memBar = document.getElementById("host-memory-bar");
    const memText = document.getElementById("host-memory-text");
    if (host.memory) {
      if (memBar) memBar.style.width = `${host.memory.usedPercent}%`;
      if (memText) {
        memText.textContent = `${formatBytes(host.memory.usedBytes)} / ${formatBytes(host.memory.totalBytes)} (${host.memory.usedPercent}%)`;
      }
    }

    const storageBar = document.getElementById("host-storage-bar");
    const storageText = document.getElementById("host-storage-text");
    if (host.storage && !host.storage.error) {
      if (storageBar) storageBar.style.width = `${host.storage.usedPercent}%`;
      if (storageText) {
        storageText.textContent = `${formatBytes(host.storage.availableBytes)} free of ${formatBytes(host.storage.totalBytes)} (${host.storage.usedPercent}% used)`;
      }
    } else if (storageText) {
      storageText.textContent = "Unavailable";
    }

    updateHotspotPanel(host.hotspot);
  }

  // --- Hotspot toggle -------------------------------------------------------
  function updateHotspotPanel(hotspotStatus) {
    const item = document.getElementById("host-hotspot-item");
    if (!item || !hotspotStatus || !hotspotStatus.supported) return;

    const statusEl = document.getElementById("host-hotspot-status");
    const labelEl = document.getElementById("host-hotspot-label");
    const btn = document.getElementById("hotspot-toggle-btn");

    if (!hotspotStatus.configured) {
      // Not-configured state has no toggle button server-side; nothing
      // to update here (would need a page reload to show the toggle
      // once configured via the CLI - the same as a newly added app).
      return;
    }

    if (statusEl) {
      statusEl.className = `status status-hotspot-${hotspotStatus.active ? "on" : "off"}`;
    }
    if (labelEl) {
      labelEl.textContent = hotspotStatus.active ? `On (${hotspotStatus.ssid})` : "Off";
    }
    if (btn && btn.getAttribute("data-pending") !== "true") {
      btn.disabled = false;
      btn.setAttribute("data-active", hotspotStatus.active ? "true" : "false");
      btn.textContent = hotspotStatus.active ? "Turn off" : "Turn on";
    }
  }

  async function toggleHotspot(btn) {
    const isActive = btn.getAttribute("data-active") === "true";
    const action = isActive ? "down" : "up";
    btn.setAttribute("data-pending", "true");
    btn.disabled = true;
    btn.textContent = "Working…";
    try {
      const res = await fetch(`/api/hotspot/${action}`, { method: "POST" });
      const data = await res.json();
      if (!res.ok || !data.ok) {
        throw new Error(data.error || `HTTP ${res.status}`);
      }
      btn.removeAttribute("data-pending");
      updateHotspotPanel(data.hotspot);
    } catch (err) {
      console.error("hotspot toggle failed", err);
      btn.removeAttribute("data-pending");
      btn.disabled = false;
      btn.textContent = isActive ? "Turn off" : "Turn on";
      await refreshStatuses();
    }
  }

  async function refreshStatuses() {
    try {
      const res = await fetch("/api/status", { cache: "no-store" });
      if (!res.ok) return;
      const data = await res.json();
      data.apps.forEach((a) => setCardStatus(a.id, a.status));
      updateSummary(data.apps);
      updateHostPanel(data.host);
      const lastScan = document.getElementById("last-scan");
      if (lastScan) {
        const now = new Date();
        lastScan.textContent = `Last scan ${now.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" })}`;
      }
    } catch (err) {
      // Best-effort - keep last known state on the page if this fails.
      console.error("status refresh failed", err);
    }
  }

  // --- Start/Stop actions ------------------------------------------------
  async function callAction(id, action) {
    setCardStatus(id, "pending");
    try {
      const res = await fetch(`/apps/${encodeURIComponent(id)}/${action}`, { method: "POST" });
      const data = await res.json();
      if (data.status) {
        setCardStatus(id, data.status);
      } else {
        await refreshStatuses();
      }
    } catch (err) {
      console.error(`${action} failed for ${id}`, err);
      await refreshStatuses();
    }
  }

  function initActions() {
    document.getElementById("grid")?.addEventListener("click", (e) => {
      const btn = e.target.closest(".start-btn, .stop-btn");
      if (!btn) return;
      e.preventDefault();
      e.stopPropagation();
      if (btn.disabled) return;
      const id = btn.getAttribute("data-app-id");
      const action = btn.classList.contains("start-btn") ? "start" : "stop";
      callAction(id, action);
    });
  }

  // --- Clock ---------------------------------------------------------------
  function tickClock() {
    const el = document.getElementById("clock");
    if (!el) return;
    const now = new Date();
    el.textContent = now.toLocaleString([], {
      weekday: "short",
      year: "numeric",
      month: "short",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit"
    });
  }

  // Full rescan: re-reads apps/<id>/manifest.json (picks up newly
  // added/removed apps and any .env port changes) server-side, then
  // reloads the page - a manifest rescan can add/remove whole cards,
  // which the lighter status-only polling below can't reflect by
  // patching the DOM in place.
  async function rescan(btn) {
    const originalText = btn.textContent;
    btn.disabled = true;
    btn.textContent = "Rescanning…";
    try {
      const res = await fetch("/api/rescan", { method: "POST" });
      if (!res.ok) throw new Error(`rescan failed: HTTP ${res.status}`);
      window.location.reload();
    } catch (err) {
      console.error("rescan failed", err);
      btn.disabled = false;
      btn.textContent = originalText;
    }
  }

  function init() {
    renderIcons();
    initFilters();
    initActions();

    document.getElementById("refresh-btn")?.addEventListener("click", (e) => rescan(e.currentTarget));
    document.getElementById("hotspot-toggle-btn")?.addEventListener("click", (e) => toggleHotspot(e.currentTarget));

    tickClock();
    setInterval(tickClock, 1000 * 30);

    const intervalMs = (window.__STATUS_POLL_SECONDS__ || 15) * 1000;
    setInterval(refreshStatuses, intervalMs);
  }

  document.addEventListener("DOMContentLoaded", init);
})();
