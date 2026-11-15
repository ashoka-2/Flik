# Known limits

- The development environment does not have Flutter installed, so Android dependency resolution, analysis, tests, and APK builds cannot run here.
- V1 payload bytes are not encrypted on the local network. Pairing tokens authenticate peers but do not protect against a network sniffer; v2 should add TLS with a certificate pinned during pairing.
- UWB support will use an interface with a safe no-op fallback until a maintained Android implementation is available.
- Physical Android and multi-device LAN behavior require real hardware verification.
