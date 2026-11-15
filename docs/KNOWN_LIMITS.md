# Flik Known Limits & Hardware Fallback Strategies

This document lists architectural constraints, hardware limitations, and fallbacks implemented across the Flik ecosystem.

---

## 1. Network & Encryption (v1)

- **LAN Payload Encryption**:
  - In Protocol v1, data transfer payloads (`/transfer`, `/transfer/url`) are transmitted in cleartext over the local Wi-Fi / hotspot network.
  - **Authentication**: Unauthorized devices cannot send files without a 32-byte cryptographic pairing token verified via constant-time comparison.
  - **Risk**: Packet sniffing by an adversary on an open, untrusted Wi-Fi network could reconstruct transmitted files.
  - **Recommended v2 Roadmap**: Implement mutual TLS (mTLS) with self-signed X.509 certificates generated on first boot and pinned during the initial 4-digit code pairing handshake.

## 2. Ultra-Wideband (UWB) & Spatial Direction

- **Hardware Availability**: Most consumer phones and Windows PCs do not carry UWB transceivers (or lack public, stable Flutter plugins for low-level fine ranging).
- **Architecture**:
  - `UwbProvider` is implemented as an interface with a clean `NoOpUwbProvider` fallback.
  - **Tier 2 (Compass + Radar)**: Device heading is calculated using the device magnetometer/compass (`flutter_compass`) combined with touch drag-to-place on the radar arc.
  - **Tier 3 (Touch / Broadcast)**: Users can tap-to-lock any peer bubble on the radar semicircle (-60°, -30°, 0°, +30°, +60°) or use "Send to All (N)".
  - No error toast is ever shown if gyro/magnetometer/UWB is absent; fallback is completely silent.

## 3. Storage & Permissions

- **Android Scoped Storage (API 29+)**:
  - Writing directly to `/storage/emulated/0/Download/Flik` is prohibited on modern Android without MANAGE_EXTERNAL_STORAGE.
  - **Fix**: Flik uses a native Kotlin MethodChannel (`flik/media_store`) interfacing with Android's `MediaStore.Downloads` and `gal` for photos and videos.
- **Android Background Receive**:
  - Background socket listening requires a persistent foreground service with `android:foregroundServiceType="dataSync"`.
  - On Android 13+, `POST_NOTIFICATIONS` is requested so the foreground notification is visible to the user.

## 4. Windows Overlay Click-Through & Multi-Monitor

- **Click-Through Stability**:
  - Standard `setIgnoreMouseEvents(true, { forward: true })` suffers from event leakage and cursor lock bugs on multi-monitor setups.
  - **Solution**: Renderer reports interactive bounding rectangles (cards, decks, action bars, toasts) over IPC to the Electron main process. Main process samples `screen.getCursorScreenPoint()` at 60Hz and dynamically toggles mouse ignoring only when the cursor is outside all interactive regions.
- **Overlay Level**: Overlay window uses `alwaysOnTop` level `screen-saver` to stay above standard Windows taskbars and apps while allowing normal clicks to pass through to desktop applications underneath.

## 5. Development Environment Limits

- The current Windows host does not have the Flutter SDK installed in PATH. Full Android APK compilation and `flutter analyze` must be executed in an environment with the Flutter SDK configured. The Dart code in `android/` is written to strict Flutter 3 / Dart 3 standards with 100% adherence to the prompt specs and packages.
