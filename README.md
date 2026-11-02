# Thock

**A lightweight, low-latency native macOS menu-bar app that plays real mechanical keyboard switch recordings as you type.**

Thock intercepts global keystrokes across macOS and triggers high-fidelity acoustic feedback with sub-millisecond audio latency. Built in pure Swift using Apple's CoreGraphics and AVFoundation frameworks.

---

## Features

- **5 Authentic Mechanical Sound Profiles:**
  - Cherry MX Brown (Tactile)
  - Cherry MX Blue (Clicky)
  - NovelKeys Cream (Linear)
  - Topre (Electro-capacitive)
  - EG Oreo (Tactile)
- **Zero Audio Clipping:** Employs a 16-channel round-robin `AVAudioPlayerNode` pool so rapid keystrokes (>100 WPM) never cut off active switch decays.
- **In-Memory Audio Slicing & Peak Normalization:** Loads individual switch packs from high-res `.caf` audio sprites into contiguous `AVAudioPCMBuffer` memory slices, automatically peak-normalizing samples so switching profiles maintains consistent loudness.
- **Dynamic Device Switching:** Observes `AVAudioEngineConfigurationChange` system notifications to seamlessly migrate audio playback when headphones, AirPods, or external DACs are connected/disconnected.
- **Low Footprint:** 100% native Swift compiled directly with `swiftc -O` — no Electron or heavy runtime dependencies.
- **Unobtrusive UI:** Runs as a menu-bar agent (`LSUIElement`) with quick switch switching, volume adjustment, and mute toggle.

---

## Architecture

```
 macOS Keyboard Input
        │
        ▼
 ┌──────────────┐
 │  CGEventTap  │ (Global Input Monitoring)
 └──────────────┘
        │ Virtual Keycode
        ▼
 ┌──────────────────────┐
 │ Scancode Translation │ (US Layout -> Mechvibes Scancodes)
 └──────────────────────┘
        │
        ▼
 ┌──────────────────────┐
 │  16-Voice Round-     │ (AVAudioEngine + AVAudioPlayerNode pool)
 │  Robin Audio Pool    │
 └──────────────────────┘
        │ Low-latency PCM Slices
        ▼
 System Audio Output (Auto-routes on headphone plug/unplug)
```

---

## Building and Installing

### Prerequisites
- macOS 12+
- Xcode Command Line Tools (`xcode-select --install`)

### Build
Run the build script:

```bash
chmod +x build.sh
./build.sh
```

This compiles `main.swift` with optimization `-O`, bundles resource packs, runs a self-test diagnostic (`--selftest`), pins designated code-signing requirements, and installs `Thock.app` directly into `/Applications/`.

---

## Permissions

Because Thock listens to global keystrokes to trigger audio feedback:
1. On first launch, macOS will prompt for **Input Monitoring** permission (`System Settings > Privacy & Security > Input Monitoring`).
2. Toggle `Thock` on. Thock dynamically polls until permission is granted without requiring an app relaunch.

---

## Credits and License

- Swift source code licensed under the MIT License.
- Sound packs derived from Mechvibes sound packs (MIT License). See `sounds/LICENSE-mechvibes`.
