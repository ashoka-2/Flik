# Flik

Flik is a local-network transfer system for Android and Windows. The monorepo keeps both clients aligned to a shared protocol.

## Repository layout

- `android/` Flutter Android client
- `windows/` Electron Windows client
- `protocol/` shared protocol schemas and fixtures
- `docs/` protocol and implementation notes
- `design/` shared UI design tokens
- `tools/` verification helpers

## Design system

Both clients use the minimal-ai-ui design language: quiet charcoal surfaces, a single blue accent, rounded grouped controls, accessible contrast, and restrained motion. Token source: `design/tokens.json`.

## Status

Foundation scaffold. Platform applications and protocol implementation are forthcoming.
