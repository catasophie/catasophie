# sdr

Web-based SDR (software-defined radio) receiver, powered by
[OpenWebRX+](https://github.com/luarvique/openwebrx). Gives you a
waterfall/spectrum display and AM/FM/SSB/digital-mode demodulation in
any browser on the LAN - useful for listening to local RF traffic
(NOAA weather radio, aviation, marine, ham, PMR/FRS, etc.) when the
grid/internet is down and you just need a radio receiver and a laptop.

Requires an RTL-SDR USB dongle plugged into the host. This is
**manual, passive listening only** - it does not automatically decode
or alert on anything (e.g. no automated NOAA/SAME emergency-alert
decoding; that's a separate, not-yet-built app - see
`docs/ROADMAP.md`).

## Hardware prerequisites (one-time, on the host, before installing)

These are host-level steps outside `install.sh`'s reach (rootless
podman can't do them for you):

1. **Blacklist the kernel's own DVB driver.** Linux's `dvb_usb_rtl28xxu`
   kernel module claims RTL-SDR dongles for TV-tuner use before
   librtlsdr (inside the container) can open them, causing a
   `usb_claim_interface error -6`. Blacklist it:
   ```sh
   echo 'blacklist dvb_usb_rtl28xxu' | sudo tee /etc/modprobe.d/blacklist-rtlsdr.conf
   sudo rmmod dvb_usb_rtl28xxu 2>/dev/null || true
   ```
   (unplug/replug the dongle, or reboot, after this)

2. **Give the dongle's USB device node permissive access** so a
   rootless podman container can open it. Add a udev rule matching
   your dongle's vendor:product ID (`lsusb` to find it - stock RTL-SDR
   dongles are usually `0bda:2838`, RTL-SDR Blog v3 is `0bda:2838` too,
   RTL-SDR v4 is `0bda:2832`):
   ```sh
   echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2838", MODE="0666"' \
     | sudo tee /etc/udev/rules.d/20-rtlsdr.rules
   sudo udevadm control --reload-rules && sudo udevadm trigger
   ```
   Adjust the vendor/product IDs if `lsusb` shows different values for
   your dongle.

Without both of these, the container will start fine but won't be
able to see the dongle at all.

## Install / run

```sh
make install ARGS="sdr"
# or directly:
./apps/sdr/install.sh
```

Then visit `http://localhost:3040/` (or whatever you set `SDR_PORT`
to - also reachable at `http://<device-ip>:3040/` from another device
on the LAN).

**One manual step after first install:** log in at
`http://localhost:3040/settings` with the admin account configured
during install, then add your RTL-SDR device and at least one
frequency profile under *Settings > SDR Devices and Profiles*.
OpenWebRX has no supported, stable file format for pre-configuring
this non-interactively, so this one step can't be scripted - it's a
one-time, few-clicks setup, analogous to this repo's other
"heavy one-time setup" steps (like `wikimed`'s ZIM download or
`offline-maps`'s region import) just manual instead of automated.

`up.sh` / `down.sh` start/stop the container without re-prompting.

## Data

Persistent data (SDR device/profile config, users database, bookmarks)
lives in `./data/` (gitignored), or wherever `DATA_DIR` in `.env`
points (e.g. an external drive) - see `install.sh`.

## Notes / limitations

- This app publishes `/dev/bus/usb` (the whole host USB bus, not a
  specific device path) into the container so it survives the dongle
  being unplugged/replugged on a different port - but that also means
  the container can see *any* USB device on the bus, not just the SDR
  dongle. Acceptable given this repo's trusted-LAN, single-purpose-
  device assumption (see `docs/ARCHITECTURE.md`), but worth knowing.
- The admin password in `.env` is stored in plaintext, like every
  other setting in this repo (see `docs/ARCHITECTURE.md`'s trusted-LAN
  threat model) - don't reuse a sensitive password here.
- Only tested with a single RTL-SDR dongle. Multiple simultaneous SDR
  devices should work (OpenWebRX supports it) but isn't specifically
  verified by this app's setup.
