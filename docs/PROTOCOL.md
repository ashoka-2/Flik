# Flik shared protocol v1

All devices advertise `_flik._tcp` and publish `deviceId`, `deviceName`, `platform`, and `ver=1` TXT records. The service port is the actual bound port (54321–54330).

## Pairing

First contact uses unauthenticated `POST /pair` with `{deviceId, deviceName, platform, nonce}`. Show a four-digit code derived from the nonce on both devices and require receiver approval within 30 seconds. Accepted pairing returns a random 32-byte token; each device stores the peer identity and token. All other routes require `X-Flik-Device-Id` and `Authorization: Bearer <token>`, compared in constant time.

## Routes

- `GET /ping` returns identity, platform, protocol version, free bytes, and busy state.
- `POST /pair` requests pairing.
- `POST /transfer` accepts multipart: first `meta` JSON with transfer ID, ordered item metadata and optional trajectory; then each file in order.
- `POST /transfer/url` accepts transfer ID and an HTTP(S) URL with optional title.
- `DELETE /transfer/:id` cancels transfer and removes partial files.

Receivers reject insufficient disk space (507), concurrent receive (409), unknown/bad credentials (401), and unsafe URLs (400). Sanitize names, deduplicate, stream to `.part`, rename only on completion, remove partials on failure, enforce a 10-second idle watchdog and rate-limit unauthenticated routes. Only HTTP(S) URLs up to 2048 characters are permitted.

V1 transfer payloads are not encrypted on the LAN. Token authentication prevents unauthorized clients but does not protect against packet sniffing. Consider TLS with pinned certificates in v2.
