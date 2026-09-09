/*
 * RESILIENCE HUB — APP CONFIG
 * ---------------------------
 * This is the only file you need to edit to add, remove, or change
 * the sub-apps on your dashboard. No build step, no server restart
 * needed on the dashboard itself — just save and reload the page.
 *
 * Each app entry:
 *   id          unique string, no spaces (used internally)
 *   name        shown on the card
 *   description one short sentence — what it's for, in plain terms
 *   category    groups cards under a heading (any string you like)
 *   protocol    "http" or "https"
 *   host        e.g. "localhost", "127.0.0.1", or a LAN IP like "192.168.1.42"
 *   port        the port the app listens on
 *   path        usually "/", change if the app needs a sub-path
 *   icon        one of: "radio","map","medkit","bolt","droplet","book",
 *               "shield","tools","camera","server" (falls back to "server")
 *
 * Set "location" and "systemName" below to whatever you like — they
 * appear in the header. Leave location blank to hide it.
 */

const APPS_CONFIG = {
  systemName: "Resilience Hub",
  location: "",

  // How often (in seconds) the dashboard re-checks whether each app
  // is reachable. Lower = more current, but more background traffic.
  statusCheckIntervalSeconds: 15,

  // How long (in ms) to wait for a service before marking it offline.
  statusCheckTimeoutMs: 2500,

  apps: [
    {
      id: "mesh-chat",
      name: "Mesh Chat",
      description: "Peer-to-peer messaging over the local network, no internet required.",
      category: "Communications",
      protocol: "http",
      host: "localhost",
      port: 8081,
      path: "/",
      icon: "radio"
    },
    {
      id: "offline-maps",
      name: "Offline Maps",
      description: "Downloaded regional maps, routes, and points of interest.",
      category: "Navigation",
      protocol: "http",
      host: "localhost",
      port: 8082,
      path: "/",
      icon: "map"
    },
    {
      id: "first-aid",
      name: "First Aid Reference",
      description: "Searchable medical reference and treatment guides.",
      category: "Medical",
      protocol: "http",
      host: "localhost",
      port: 8083,
      path: "/",
      icon: "medkit"
    },
    {
      id: "power-monitor",
      name: "Power Monitor",
      description: "Battery bank, solar input, and generator status.",
      category: "Power & Utilities",
      protocol: "http",
      host: "localhost",
      port: 8084,
      path: "/",
      icon: "bolt"
    },
    {
      id: "water-log",
      name: "Water & Supplies Log",
      description: "Track water purification cycles and food inventory.",
      category: "Power & Utilities",
      protocol: "http",
      host: "localhost",
      port: 8085,
      path: "/",
      icon: "droplet"
    },
    {
      id: "field-manual",
      name: "Field Manual Library",
      description: "Offline copies of survival, repair, and reference manuals.",
      category: "Reference",
      protocol: "http",
      host: "localhost",
      port: 8086,
      path: "/",
      icon: "book"
    },
    {
      id: "security-cams",
      name: "Camera Feeds",
      description: "Local security and perimeter camera streams.",
      category: "Security",
      protocol: "http",
      host: "localhost",
      port: 8087,
      path: "/",
      icon: "camera"
    },
    {
      id: "weather-station",
      name: "Weather Station",
      description: "Readings from the local weather sensor array.",
      category: "Navigation",
      protocol: "http",
      host: "localhost",
      port: 8088,
      path: "/",
      icon: "shield"
    }
  ]
};
