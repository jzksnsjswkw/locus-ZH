# Locus

Free and open-source iPhone location teleport. Tap the map, search a place, or drive a route — Locus injects coordinates through Apple's private **CLSimulationManager** API into `locationd`, so Maps and other apps see the spoofed GPS (not just a Wi‑Fi lookup that outdoor GPS will overwrite).

Works on **iOS 16.0+**. Install with **TrollStore** — no pairing file, no developer tunnel, no computer, no Developer Mode.

<p align="center">
  <img src="docs/screenshots/map.png" alt="Locus map with spoof pin" width="180" />
  <img src="docs/screenshots/spoofing.png" alt="Locus spoofing in 3D" width="180" />
  <img src="docs/screenshots/joystick.png" alt="Locus joystick controls" width="180" />
  <img src="docs/screenshots/route.png" alt="Locus route on map" width="180" />
</p>

## Features

- One-tap teleport (map pin or place search)
- Live joystick — walk / run / cycle / drive with light speed variation
- Walk/Drive routing on real roads & footpaths (MapKit)
- Draw a path or import / export GPX
- Background keep-alive + live status bar + drop alerts
- Favorites & recents
- First-run welcome
- Fully on-device — no analytics, nothing uploaded

## Install

See [SETUP.md](SETUP.md) for full steps. Grab a prebuilt `.tipa` from [Releases](https://github.com/ChrisMack32/Locus/releases), or build from source below.

Bundle ID: `com.chrismack.locus`

**Requirement:** install Locus with **TrollStore**. The app must keep the `com.apple.locationd.simulation` entitlement when re-signed, and TrollStore is the only sideloader that preserves arbitrary entitlements. If you install with normal signing, the simulation API silently does nothing.

## How it works

Locus talks to Apple's private `CLSimulationManager` (CoreLocation) — the same API used by Geranium, Andromeda, TrollTools, and locsim. It injects simulated coordinates system-wide into `locationd`:

- No pairing file, no developer tunnel, no LocalDevVPN, no Developer Mode, no computer.
- The entitlement `com.apple.locationd.simulation` is what grants access (preserved by TrollStore's fake-root re-signing).
- The simulation is system-wide and **persists after Locus is killed** — it lives in `locationd`. It clears when `locationd` restarts or the device reboots.
- Start a teleport; Locus keeps a light background session so the fix stays fresh while the app is open.

### Pokémon GO & similar games

Locus spoofs location the same way Apple's own simulator does: it tells iOS "you're here," and other apps read that from the system. Apps that just trust GPS (Apple Maps, etc.) will follow it.

**Pokémon GO is different.** It runs its own location checks and often rejects developer / simulated GPS (e.g. "Failed to detect location"). That's expected with this method, not a Locus bug, and there's no supported fix for it in this app.

Tools like **iPogo** (and similar modified clients such as SpooferPro) work differently: they're a **modified Pokémon GO app**, not a system-wide location spoof. Features live *inside* that altered game client, instead of feeding coordinates through iOS for every app. Locus never patches or replaces Pokémon GO; it only changes what the system reports. So those tools can appear to "work in Pokémon GO" while Locus correctly drives Maps but still gets blocked by Pokémon GO's checks.

Locus is for system-level teleporting. It isn't a Pokémon GO client or an anti-cheat bypass.

## Build

Building from source needs an Apple Developer account (free or paid) for code signing. The published `.tipa` does **not** — just sideload it with TrollStore.

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if needed: `brew install xcodegen`
2. Set your **Team ID** in `project.yml` (`DEVELOPMENT_TEAM`), *or* pick your team under Xcode → Signing & Capabilities after generating the project.
3. Generate and open:

```bash
xcodegen generate
open Locus.xcodeproj
```

Or build from the CLI (replace with your Team ID from [developer.apple.com/account](https://developer.apple.com/account) → Membership):

```bash
xcodegen generate
xcodebuild -project Locus.xcodeproj -scheme Locus -configuration Release \
  -destination 'generic/platform=iOS' DEVELOPMENT_TEAM=YOUR_TEAM_ID build
```

### Packaging for TrollStore

Build unsigned, fake-sign with `ldid -S` using the entitlements, and zip as a `.tipa`:

```bash
xcodebuild -project Locus.xcodeproj -scheme Locus -configuration Release \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build build
APP=build/Build/Products/Release-iphoneos/Locus.app
ldid -SLocus/Resources/Locus.entitlements "$APP/Locus"
cd build/Build/Products/Release-iphoneos && zip -r Locus.tipa Payload
```

Then install `Locus.tipa` with TrollStore.

## License

MIT. Locus is an independent open-source project and is not affiliated with Mirage / Wapixel.
