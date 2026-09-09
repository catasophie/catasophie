# Roadmap

Candidate apps/tools for future phases, roughly in suggested priority
order. None of these are scaffolded yet - use `make add-app` and
`docs/ADDING_AN_APP.md` when picking one up.

## Near-term

- **Broader offline encyclopedia (Kiwix)** - `apps/wikimed` already
  implements the Kiwix fetch/serve pattern (survival medicine ZIMs by
  default, extensible catalog); this item is about adding more general
  ZIMs on top - Wikipedia, Wiktionary, WikiHow, Project Gutenberg -
  either by extending `apps/wikimed`'s catalog or as a separate app.
- **Inventory & rationing tracker** - food/water/fuel/medical supplies
  with expiry tracking and days-remaining-at-current-usage estimates.
  Simple CRUD app, high daily-use value even outside an actual emergency.
- **Mesh networking bridge (Meshtastic/Reticulum)** - text messaging over
  LoRa with no infrastructure; biggest capability jump for multi-person
  coordination during an outage. Needs `requires_host_device`-style USB
  passthrough for the LoRa radio.
- **Automated NOAA/SAME emergency-alert monitor** - `apps/sdr` already
  implements general-purpose web SDR (OpenWebRX+) for manual/passive
  listening with an RTL-SDR dongle; this item is about a separate,
  headless service (`rtl_fm`/`multimon-ng`-style pipeline) that decodes
  NOAA Weather Radio SAME headers automatically and logs/alerts on
  severe-weather/EAS codes without anyone needing to watch a browser.
  Also needs USB device passthrough (see `apps/sdr` for the pattern).

## Later

- **Static first-aid quick-reference / triage checklist app** - fast,
  no-LLM-needed reference for the most common emergencies, and a
  decision-tree triage app that works even if the LLM container is down.
- **Local sensor dashboard** (temp/humidity/CO, freezer/fridge alarms,
  solar charge controller / well pump status via Modbus) - Home
  Assistant-style, fully offline.
- **Document library / manuals repo** - searchable repair manuals, water
  purification, food preservation guides beyond the survival/medical
  corpus.
- **Task/duty roster + barter ledger** - for multi-person groups.
- **Local intrusion/camera monitoring** (e.g. Frigate) if IP cameras are
  present.
- **Encrypted local backup vault** for scanned documents (IDs, insurance,
  deeds).
- **GPS track logger / offline star chart & compass / tide tables** -
  navigation aids beyond routed driving directions.

## Cross-cutting, not app-specific

- **Power monitor** (laptop battery via `/sys/class/power_supply`, UPS via
  NUT, or a Pi HAT via I2C) - useful across every app, could be a small
  status widget/its own app publishing its own port.
- **Auth**, per-app, if a box is ever exposed beyond a fully trusted LAN
  (see `docs/ARCHITECTURE.md`) - each app is independent with no shared
  proxy, so this would be added per-app (Open WebUI already has its own
  login, for example).
- **Backup/restore script** for each app's `data/` directory.
