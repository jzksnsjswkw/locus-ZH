# Locus — install & first teleport

## 1. Install the .tipa with TrollStore

Get the prebuilt `Locus.tipa` from [Releases](https://github.com/jzksnsjswkw/locus-ZH/releases) (or build from source), then:

1. Open **TrollStore** → **Settings** → **Install .tipa / .ipa** (or share the file into TrollStore).
2. Select `Locus.tipa` → **Install**.
3. Launch Locus.

Bundle ID: `com.chrismack.locus`

**Why TrollStore:** Locus calls Apple's private `CLSimulationManager` API, which requires the `com.apple.locationd.simulation` entitlement. TrollStore re-signs apps with its fake root certificate and **preserves arbitrary entitlements**; normal sideloaders strip them, and the simulation silently stops working. No pairing file, no tunnel, no computer, no Developer Mode needed.

## 2. First run

1. Open Locus. Allow **Location** when asked (used to aim the map / return home) and **Notifications** (drop alerts).
2. Tap **Get started**, drop a pin on the map, tap **开始定位** (Start).

## 3. Teleport

- **Pin:** tap the map to drop a pin, then tap **开始定位**.
- **Search:** search a place or paste coordinates, then teleport from the result.
- **Joystick:** tap **摇杆** to move continuously; **暂停 / 停止定位** to freeze or clear.
- **Routes:** plan a road route, draw a path, or import / export GPX from the route sheet.

The simulation is **system-wide** and **persists even after Locus is closed** — it lives in `locationd`. It clears when `locationd` restarts or the iPhone reboots. If a spoof ever seems stuck, reboot the device.

## Supported iOS

iOS **16.0 through 18.x** (and later) via TrollStore. iOS 27+ is fine too — the on-device pairing flow of the original Locus is not used; this build relies purely on the CLSimulationManager entitlement.

## LiveContainer

Locus is designed for TrollStore; it does not need LiveContainer. If you install it under LiveContainer, note that the simulation entitlement may not survive that container's signing.
