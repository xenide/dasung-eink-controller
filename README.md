# Dasung Control

A native Apple Silicon menu bar app for Dasung Paperlike e-ink monitors. It replaces Dasung's
Intel-only "Paperlike Series E-ink Monitor Client" and has been tested with a Paperlike 133K.

- Refresh the screen, switch display mode (M1–M4), and set contrast (1–9)
- Front light: Off / Cold / Warm / Mixed, brightness, and color temperature
- Global shortcuts that work from any app
- Optionally disables macOS display dithering and re-applies it after display changes and wake
- Connects automatically when the monitor's USB cable is plugged in

## Install

Requires Xcode 26 or later and macOS 15 or later.

```sh
scripts/bundle.sh
ditto "build/Dasung Control.app" "/Applications/Dasung Control.app"
open "/Applications/Dasung Control.app"
```

The monitor's USB cable must be connected to the Mac; the HDMI/USB-C video link alone isn't
enough. Quit Dasung's own client and remove it from Login Items first, because it locks the
monitor's serial port.

## Shortcuts

| Keys | Action |
|------|--------|
| ⌃⌥⌘R | Refresh screen |
| ⌃⌥⌘M | Next display mode |
| ⌃⌥⌘= / ⌃⌥⌘− | Contrast up / down |
| ⌃⌥⌘] / ⌃⌥⌘[ | Front light brighter / dimmer |

When the panel is open, Return refreshes the screen.

## Development

```sh
swift test
swift format lint --strict -r Sources Tests Package.swift
prek run --all-files
```

## Protocol

The monitor contains a CH340 USB-serial bridge (`1a86:7523`) running at 115200 8N1. Commands are
24 ASCII hex characters:

```
5FF5 <register> <value> 000000000000 A0FA
```

| Register | Meaning | Values |
|----------|---------|--------|
| `01` | Contrast | 1–9 |
| `02` | Display mode | 133K: M1 `06`, M2 `02`, M3 `03`, M4 `07` |
| `03` | Refresh | `00` |
| `07` | Front light | Off `00`, Cold `01`, Warm `02`, Mixed `03` |
| `08` | Color temperature | 0–100 |
| `09` | Brightness | 0–100 |
| `0A` | Query | value = register to read |
| `10` | Controller version (read only) | front light present when `30`/`31` |
| `13` | Model version (read only) | selects the display mode table |

Replies use the same framing:

- `5FF5 F0 0A <register> <value> …` answers a query
- `5FF5 F0 <register> 00 …` acknowledges a command
- `5FF5 <register> <value> …` reports a change made on the monitor

The monitor drops commands sent less than about 60 ms apart, so the app spaces them 80 ms apart.
