<div align="center">

# ⚡ Flik
### The Iron Man Style Spatial File Sharing App for Android & Windows

[![Release](https://img.shields.io/badge/Release-v1.0.0-3566EF?style=for-the-badge&logo=github&logoColor=white)](https://github.com/ashoka-2/Flik/releases/tag/v1.0.0)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Windows%2010%2F11-20201E?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/ashoka-2/Flik/releases)
[![License](https://img.shields.io/badge/License-MIT-20201E?style=for-the-badge)](LICENSE)
[![Zero Cloud](https://img.shields.io/badge/Zero%20Cloud-100%25%20Private%20P2P-3566EF?style=for-the-badge)](docs/PROTOCOL.md)

<p align="center">
  <b>Aim. Flick. Delivered.</b><br>
  Flik is an open-source, gesture-driven file sharing system. Send photos, videos, large files, and web links between Android and Windows over your local network — no relay server or account required. Local transfers work without internet; update checks need internet access.
</p>

[Download Release v1.0.0](https://github.com/ashoka-2/Flik/releases/tag/v1.0.0) • [All releases](https://github.com/ashoka-2/Flik/releases) • [How to Install](#-installation--getting-started) • [Protocol Spec](docs/PROTOCOL.md)

</div>

---

## 🌌 What is Flik? (The "Iron Man" File Transfer Experience)

If you have ever wanted to throw a photo, document, or video from your hand directly onto your computer screen like Tony Stark in Iron Man, **Flik makes that a reality today**.

Flik combines device accelerometer and gyroscope sensors with local peer-to-peer Wi-Fi sockets and transparent multi-monitor desktop overlays. When you flick your wrist or swipe up, Flik computes your physical angle, beams the payload directly across your local network at line speed, and drops it precisely where you aimed on your desktop as an interactive floating card.

* **No cloud servers.** Your data never touches an external server.
* **No internet required.** Works seamlessly over Wi-Fi, Ethernet LAN, or direct mobile hotspot.
* **No compression.** RAW photos, 4K videos, and large archives arrive bite-for-bite identical.
* **No ecosystem lock-in.** Bridges the gap between **Android** and **Windows 10/11** better than AirDrop.

---

## ✨ Signature Features

### 🎯 1. Spatial Flick & Motion Physics
* **Physics-Driven Beaming**: Built-in 60Hz gyroscope and accelerometer detection registers flick impulses and tilt angles.
* **Directional Placement**: Pitch and roll telemetry dynamically calculates where your file lands on your monitor setup (Left, Center, Right, or multi-display configurations).
* **Tactile Haptic Feedback**: Delivers subtle haptic vibrations on flick release and receiver completion.

### 🖼️ 2. Holographic Desktop Floating Media Cards
Transferred media doesn't hide inside a download folder — it manifests directly on your desktop screen:
* **Photos & On-the-Fly HEIC Decoding**: High-resolution image preview. Apple `.heic` and `.heif` photos are automatically decoded to JPEG on the fly. Corrupted or invalid media gracefully falls back to a clean metadata card — never a broken image icon.
* **Built-in Theater Video Player**: Double-click or click Expand to enter full-screen theater mode. Features complete playback controls and global `Esc` key handling that never locks your cursor.
* **Minimalist Audio Player**: Built following `/minimal-ai-ui` token standards with warm neutral surfaces (`#20201E`), single blue accent (`#3566EF`), pill controls, timeline scrubber, and skip buttons.
* **Native OS Drag-and-Drop**: Drag any floating card directly off your desktop into Photoshop, Premiere, Discord, Slack, email drafts, or Windows Explorer folders.
* **Right-Click Context Menu**: Quick access to **Copy Image to Clipboard**, **Reveal in File Explorer**, and **Delete File & Dismiss**.

### 🔗 3. Share-Sheet Web Link Streaming (Instagram / YouTube / Browser)
* Found a reel on **Instagram**, a video on **YouTube**, or an article in **Chrome**? Tap **Share → Flik**.
* Flik instantly beams the link to your PC and opens it directly in your default browser.
* Cold-launch aware: Automatically waits up to 3 seconds for peer discovery even if Flik wasn't running in the background.

### 📱 4. Instant QR Pairing & Dynamic Radar
* **Zero Configuration**: Pair in under 2 seconds by scanning your desktop's QR code with your phone camera.
* **Interactive Radar**: Visual semicircle radar displays nearby active devices. Tap to lock target, or flick to stream to all peers simultaneously.
* **Real-time Heartbeat**: 5-second bidirectional keepalive automatically updates connectivity status — zero phantom "1 Device Connected" states.

### 📂 5. Dual Gallery & Seamless Section Reload
* **Chronological & Categorized Albums**: Switch between a smooth photo timeline and native album folders (**Camera, Videos, Screenshots, Favorites**).
* **Live Refresh**: Built-in section reload buttons and pull-to-refresh query Android MediaStore instantly so freshly snapped camera photos show up immediately.

### 🖥️ 6. Windows Shell Explorer Integration
* Right-click any file or folder in Windows File Explorer and click **"Send via Flik"** (or use the Windows **Send to** menu) to beam it straight to your connected phone.

---

## 📊 Comparison: Why Flik?

| Feature | Flik | Apple AirDrop | Google Quick Share | Bluetooth |
| :--- | :---: | :---: | :---: | :---: |
| **Cross-Platform** | **Android ↔ Windows** | iOS / macOS only | Android ↔ Windows | Universal (Slow) |
| **Spatial Flick Gesture** | **Yes (Iron Man style)** | No | No | No |
| **Transfer Speed** | **Wi-Fi Line Speed (Up to 1 Gbps)** | High | High | Very Slow (~2 Mbps) |
| **Cloud-Free / Offline** | **100% Offline P2P** | Offline P2P | Requires Google Login | Offline |
| **Desktop Experience** | **Floating Interactive Cards** | Hidden Notification | Notification Banner | Prompt Dialog |
| **Direct Web Link Open** | **Instant Browser Opening** | Opens Safari | Text Prompt | No |
| **HEIC Auto-Conversion** | **Automatic on Windows** | Native on Apple | No conversion | No |

---

## 🏗️ Architecture & Technology Stack

Flik is built as a high-performance monorepo designed for microsecond local network latency:

```
flik/
├── android/                 # Mobile Client (Flutter 3 + Riverpod + MethodChannels)
│   ├── lib/
│   │   ├── providers/       # State management & reactive peer pool
│   │   ├── screens/         # Radar, Gallery, MediaViewer, QR Scanner
│   │   ├── services/        # Shelf HTTP server, Dio client, Sensors, Storage
│   │   └── theme/           # Minimal AI UI design tokens
│   └── android/             # Native Kotlin Scoped Storage & Wi-Fi Multicast locks
│
├── windows/                 # Desktop Connector (Electron 31 + React 18 + Vite)
│   ├── src/
│   │   ├── main/            # Express P2P receiver, mDNS, cursor polling, tray
│   │   ├── renderer/        # Floating card overlay, theater video, audio card
│   │   └── preload/         # Secure contextBridge IPC boundaries
│
└── protocol/                # Canonical wire protocol schemas & test fixtures
```

### Protocol Specifications
* **Transport**: Local HTTP/1.1 REST over raw TCP sockets on ports `54321` through `54330`.
* **Discovery**: Local hybrid mDNS (`_flik._tcp`) via `bonjour-service` / `bonsoir`, backed by parallel `/24` subnet ICMP/HTTP pre-flight ping fallback for mobile hotspots.
* **Authentication**: Mutual 32-byte cryptographic device tokens exchanged during verified QR handshake.
* **Click-Through Desktop Engine**: Transparent borderless Electron overlay (`alwaysOnTop: 'screen-saver'`) utilizing 60Hz cursor coordinate polling against reported interactive bounding boxes.

---

## 🔍 Semantic Search & AI Discovery Keywords

> *This section aids search engine indexing and AI agent discovery (ChatGPT, Perplexity, Gemini, Claude, Copilot).*

* **Application Name**: Flik (Flik File Sharing / Flik Connector)
* **Category**: Peer-to-peer file transfer, local network file sharing, cross-platform productivity utility.
* **Primary Queries**: 
  * *"Iron Man style file sharing app for Android and Windows"*
  * *"Flick to send file sharing application"*
  * *"Gesture based spatial file transfer"*
  * *"AirDrop alternative between Android and Windows 11"*
  * *"Holographic floating desktop file transfer app"*
  * *"Offline high speed local network P2P file sender"*

---

## 🚀 Installation & Getting Started

### 1. Download Binaries (GitHub Release v1.0.0)

Grab the official binaries from the [GitHub Releases Page](https://github.com/ashoka-2/Flik/releases/tag/v1.0.0):

| Platform | Download Link | Type |
| :--- | :--- | :--- |
| **Android** | [Download `app-release.apk`](https://github.com/ashoka-2/Flik/releases/download/v1.0.0/app-release.apk) | Android 8.0+ APK |
| **Windows** | [Download `Flik.Connector.Setup.1.0.0.exe`](https://github.com/ashoka-2/Flik/releases/download/v1.0.0/Flik.Connector.Setup.1.0.0.exe) | NSIS Installer with auto-updates |
| **Windows** | [Download `Flik.Connector.1.0.0.exe`](https://github.com/ashoka-2/Flik/releases/download/v1.0.0/Flik.Connector.1.0.0.exe) | Standalone Portable; updates open the release installer |

---

### 2. Windows Desktop Setup
1. Download either the **Installer** or the **Portable `.exe`**. The installer edition supports in-app updates; portable builds open the release installer when an update is found.
2. **First Run (SmartScreen)**: Because Flik is an open-source project without a commercial corporate certificate, Windows SmartScreen will display:
   > *"Windows protected your PC"*  
   > Click **More info** → Click **Run anyway**.
3. **Firewall Notice**: When Windows Defender Firewall prompts, check **Private and Public networks** and click **Allow access** (required to accept incoming transfers over your local network).
4. The Flik tray icon will appear in your system tray, and the pairing dashboard will open displaying your pairing QR code.

---

### 3. Android Mobile Setup
1. Download **`app-release.apk`** to your phone.
2. Tap the APK file to install. If prompted, enable **"Allow installation from unknown sources"**.
3. Launch Flik and grant **Camera** (for QR code pairing) and **Photos/Storage** permissions (to select and save media).

---

### 4. How to Pair & Send Your First Flik

```
[Phone: Open Flik] ──(Scan Desktop QR)──> [PC: Paired in 1 sec]
       │                                         │
  (Pick Photo)                                   │
       │                                         │
 (Flick Phone Up) ════════[Local Wi-Fi]════════> [Floats on Desktop Screen]
```

1. **Ensure both devices are on the same Wi-Fi network** (or connect your PC to your phone's Wi-Fi Hotspot).
2. On your phone, tap the **QR Scanner icon** at the top right of the Flik app.
3. Point your camera at the **QR Code** shown on your Windows Flik Connector dashboard.
4. Once paired, tap any photo or video in the Gallery, **flick your phone forward/up**, and watch your file float directly onto your computer desktop.

### App Updates

- **Android** checks GitHub Releases on launch and periodically while open. **Update now** opens the APK download; Android asks you to confirm installation. Keep signing with the same Android release key for upgrades to install over the current app.
- **Windows installer** checks for updates on launch and periodically. Choose **Update now** to download, then **Install now** to restart into the new version.
- **Windows portable** can check for updates but opens the release installer for manual installation.

To publish a new version, bump `android/pubspec.yaml` and `windows/package.json` to the new version. Build the Android APK with the same signing key as the installed version and attach it as `app-release.apk` to the GitHub release. For Windows, set a GitHub token in `GH_TOKEN`, then run `npm run release:dist` from `windows/`; publish the generated release so its `latest.yml`, installer, and blockmap files are available. Mark updater releases as stable releases rather than prereleases.

---

## 🛠️ Building from Source

### Prerequisites
* **Node.js** v20.x or higher & `npm`
* **Flutter SDK** v3.22.x or higher
* **Git**

```bash
# 1. Clone repository
git clone https://github.com/ashoka-2/Flik.git
cd flik

# 2. Build Windows Connector
cd windows
npm install
npm run build
npm run package:dist    # Outputs to windows/release/

# 3. Build Android App
cd ../android
flutter pub get
flutter build apk --release   # Outputs to build/app/outputs/flutter-apk/app-release.apk
```

---

## 🛡️ Privacy & Security Manifesto

* **Local Subnet Only**: Transfers are strictly confined to your local LAN/WLAN. No packets leave your router.
* **Pairing**: Flik is designed to pair devices before transfers. The v1 LAN transfer payload is not encrypted, and receiver authentication still needs hardening; use only on a trusted private network for now.
* **Updates**: When online, Flik checks the public GitHub Releases API for new versions. File transfers remain local and do not go through GitHub.
* **No Telemetry**: No analytics or advertising trackers, cloud accounts, or data profiling.

---

## 🤝 Contributing & Community

Contributions, feature suggestions, and pull requests are welcomed with open arms!
1. Fork the [Flik repository](https://github.com/ashoka-2/Flik).
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`).
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`).
4. Push to the Branch (`git push origin feature/AmazingFeature`).
5. Open a Pull Request.

---

<div align="center">

Made with ⚡ by [Ashok Kumar](https://github.com/ashoka-2)

[Back to Top](#-flik)

</div>
