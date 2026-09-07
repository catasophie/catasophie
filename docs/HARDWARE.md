# Hardware Notes

## Supported profiles

| Profile | Typical spec | Notes |
|---|---|---|
| Raspberry Pi | Pi 4/5, 4-8GB RAM | Most constrained. Prefer smaller LLM models (1-3B), single map region, lazy-start everything. SD cards are fragile - use a USB SSD if possible, and back up regularly. |
| Mini PC | x86, 16GB+ RAM | Comfortable headroom for 7B-13B models and larger map regions. |
| Laptop | x86/ARM, 16GB+ RAM, built-in battery | Same as mini PC, plus power monitoring works out of the box via the OS battery (no extra hardware needed). |

The first-boot setup wizard auto-detects the profile (checks
`/proc/device-tree/model` for "Raspberry Pi", falls back to checking for a
battery to guess "laptop", otherwise "mini-pc") and suggests an LLM model
size accordingly. You can override the detected profile in the wizard.

## Power monitor backends

| Backend | Hardware required | Status |
|---|---|---|
| `laptop` | None - reads `/sys/class/power_supply` via the OS | Implemented |
| `nut` | A UPS with USB/serial output, monitored via Network UPS Tools (`upsc`) | Implemented (requires a NUT server/config for your specific UPS) |
| `pi-i2c` | A fuel-gauge/UPS HAT (e.g. PiJuice, Geekworm UPS) wired over I2C | Not yet implemented - stubbed. Raspberry Pi has no built-in battery reporting; without a HAT, use `POWER_BACKEND=none`. |

Set `POWER_BACKEND=auto` (default) to let the dashboard pick automatically,
or force one explicitly in `.env`.

## Storage

- Map data (per region) and knowledge corpus files (ZIM archives, vector
  DB) can be several GB each. Prefer an external SSD/USB drive over an SD
  card on Raspberry Pi for both capacity and reliability.
- Run `./scripts/backup.sh` regularly, ideally to a separate external
  drive, given SD card failure risk.

## USB device passthrough (future tools: radio/SDR, etc.)

Tools that declare `requires_host_device` in their manifest need their
device path passed through to the container and a stable udev rule so the
path doesn't shift across reboots. `scripts/doctor.sh` checks that
declared device paths exist and are accessible.

## Antenna guidance (radio module, when added)

- VHF/UHF (NOAA weather radio ~162MHz, FM broadcast, airband) needs a
  much shorter antenna than HF/shortwave (1.8-30MHz).
- HF/shortwave reception on a plain RTL-SDR dongle needs direct-sampling
  mode (e.g. RTL-SDR Blog V3) or an upconverter - a stock dongle alone
  won't tune below ~24-28MHz well.
