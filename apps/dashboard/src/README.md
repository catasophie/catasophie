# Resilience Hub

A single-page dashboard that lists every sub-app in your project and lets you
jump to whichever one you need. Built to run with zero internet access and
no build tools — it's plain HTML/CSS/JS.

## Files

```
index.html       the page itself
style.css        styling
app.js           rendering + status-check logic
apps-config.js   <-- edit this to add/change your apps
```

## 1. Add your apps

Open `apps-config.js` and edit the `apps` array. Each entry needs a name,
description, category, host, port, and an icon key. See the comments at the
top of the file for the full field list. No other file needs to change —
add as many apps as you want, in as many categories as you want.

## 2. Run it

The dashboard is a set of static files, so you have two options:

**Option A — just open it.** Double-click `index.html`. This works, but the
live status checks (see below) are more reliable when served over HTTP
rather than opened directly from disk, since some browsers restrict what a
`file://` page can do.

**Option B — serve it (recommended).** From this folder, run a tiny local
server and leave it running alongside your other apps:

```bash
# Python (usually already installed)
python3 -m http.server 8000

# or Node, if you have it
npx serve -l 8000
```

Then open `http://localhost:8000` as your single entry point. Bookmark it,
or set it as the browser's home page / start page on the machine you'll use
during an outage.

## 3. Start your sub-apps

This dashboard doesn't launch the other apps for you — it assumes you (or a
startup script) bring up each sub-app on its configured host and port
separately. A simple approach that fits a "start the whole project" workflow
is a shell script that starts every service plus this dashboard's server,
e.g.:

```bash
#!/usr/bin/env bash
# start-all.sh — example, adjust paths/commands to your real apps
(cd mesh-chat && ./run.sh) &
(cd offline-maps && ./run.sh) &
(cd first-aid && ./run.sh) &
(cd resilience-hub && python3 -m http.server 8000) &
wait
```

The dashboard just needs each app's host:port to match what's in
`apps-config.js`.

## How the "online / offline" status works

The dashboard can't read HTTP status codes across origins without CORS
support from each sub-app, so it uses a best-effort reachability check: it
tries to open a connection to each app's URL and times out after 2.5
seconds (configurable via `statusCheckTimeoutMs`). If the connection
opens, the app is marked online; if it times out or errors, it's marked
offline. This is a reasonable signal for "is this app up," not a
guarantee — a firewall or a slow app can occasionally cause a false
offline reading. It re-checks automatically every 15 seconds (configurable
via `statusCheckIntervalSeconds`), or on demand with the "Rescan" button.

## Notes for offline/low-power use

- No external fonts, CDNs, or analytics — everything needed is in these
  four files, so it works with no internet connection at all.
- Uses only fonts already installed on the OS.
- Flat, low-animation UI to stay legible and cheap to render on old or
  low-power hardware (e.g. a Raspberry Pi driving a small screen).
- Respects `prefers-reduced-motion`.
- Works on a phone or tablet screen if that's what's available.

## Customizing further

- **Colors / look**: all in `style.css`, defined as CSS variables at the
  top (`--bg`, `--amber`, `--green`, `--red`, etc.).
- **Icons**: `app.js` has a small built-in icon set (`radio`, `map`,
  `medkit`, `bolt`, `droplet`, `book`, `shield`, `tools`, `camera`,
  `server`). Add more by adding an SVG path string to the `ICONS` object.
- **Categories**: just set whatever `category` string you want per app in
  `apps-config.js` — the dashboard groups and filters by whatever values
  it finds, no separate list to maintain.
