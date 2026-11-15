# Flik

> Private, local-network file and link transfer system between Android phones and Windows 10/11 PCs. No cloud, no accounts, zero internet data usage.

---

## 1. Monorepo Overview

```
flik/
  docs/
    UI_DESIGN_SKILL.md     # Minimal AI UI tokens & design standard
    PROTOCOL.md            # Canonical wire protocol specification
    KNOWN_LIMITS.md        # Hardware limitations & fallback strategies
  protocol/
    schemas & fixtures     # JSON schemas & verified test vectors
  windows/                 # Electron + React + TypeScript + Vite app
  android/                 # Flutter + Riverpod mobile app
  tools/                   # Integration verification tools & mock clients
```

---

## 2. Tech Stack

- **Design System**: `minimal-ai-ui` tokenized architecture (calm neutral surfaces, one blue accent `#3566EF`, 28px card radii, pill controls, zero emoji icons).
- **Windows (Electron)**:
  - Electron 31 + React 18 + TypeScript + Vite.
  - Express server on ports 54321–54330 with mDNS (`bonjour-service`) broadcasting `_flik._tcp`.
  - Transparent full-screen overlay per display (`alwaysOnTop` level `screen-saver`).
  - 60Hz cursor polling click-through architecture based on reported interactive rects.
  - Stacking cards deck with "X together." toolbar and native drag-out via `startDrag`.
  - Packaging: NSIS + Portable for Windows with automatic Defender Firewall rule creation.
- **Android (Flutter)**:
  - Flutter 3 (API 26+) with Riverpod state management.
  - Network discovery via `bonsoir` with parallel local /24 subnet probe fallback.
  - Cleartext HTTP permitted via `network_security_config.xml`.
  - Android 14+ Foreground Service (`dataSync`) for background reception.
  - Scoped Storage MediaStore Kotlin MethodChannel (`saveToDownloads`) for API 29+.
  - Spatial semicircle radar arc (-60° to +60°) with tap-to-lock, drag-to-place, compass heading.
  - Accelerometer wrist-flick detection with cooldown and magnitude thresholds.

---

## 3. Running & Building

### Protocol Verification & Integration Tests
```bash
# Verify schemas and vector fixtures
node tools/verify-protocol.mjs

# Run automated integration tests (mock receiver + fake phone sender)
node tools/run-integration-tests.mjs
```

### Windows Flik Connector (`windows/`)
```bash
cd windows

# Install dependencies
npm install

# Typecheck TypeScript (renderer & Electron main)
npm run typecheck

# Build renderer and Electron main
npm run build

# Start local app in Electron
npm start

# Package for Windows (NSIS installer + portable exe)
npm run package:dist
```

### Android Flik App (`android/`)
```bash
cd android

# Fetch Flutter dependencies
flutter pub get

# Run static analysis
flutter analyze

# Build debug APK
flutter build apk --debug
```

---

## 4. Known Limits & Hardware Fallback

See [docs/KNOWN_LIMITS.md](docs/KNOWN_LIMITS.md) for details on:
1. Cleartext LAN payloads in v1 (protected by 32-byte cryptographic token; v2 roadmap adds pinned-cert mTLS).
2. Ultra-Wideband (UWB) implemented behind a safe `NoOpUwbProvider` fallback; spatial positioning works seamlessly via compass and radar drag-to-place.
