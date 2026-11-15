# Flik Shared Wire Protocol (v1)

This document is the single source of truth for communication between Flik clients (Android) and servers/receivers (Windows and Android).

---

## 1. Discovery (mDNS)

- **Service Type**: `_flik._tcp`
- **Port Range**: 54321 to 54330 (fallback to next port if occupied)
- **TXT Records**:
  - `deviceId`: Persistent UUID v4 string identifying the device.
  - `deviceName`: Human-readable device name (e.g. "Ashok's PC", "Pixel 8").
  - `platform`: `android` | `windows`
  - `ver`: `1`

---

## 2. Identity & Pairing

1. **Unpaired Contact**:
   - Sender issues `POST /pair` with payload:
     ```json
     {
       "deviceId": "string (uuid-v4)",
       "deviceName": "string (1-64 chars)",
       "platform": "android" | "windows",
       "nonce": "string (min 16 chars)"
     }
     ```
   - No authentication headers are required on `/pair`.
2. **Confirmation Code**:
   - Both sender and receiver derive a 4-digit numeric code from the `nonce` using SHA-256:
     `code = (sha256(nonce)[0..3].toUInt() % 9000 + 1000).toString()`
   - The receiver prompts the user: *"Connect with [deviceName]?"* displaying the 4-digit code.
   - Pending pairing requests automatically expire after 30 seconds.
3. **Acceptance / Decline**:
   - On user Accept, receiver generates a secure random 32-byte hex/base64 string (`token`), records the peer in its trusted store, and responds:
     ```json
     {
       "status": "accepted",
       "token": "<32-byte-token-hex>"
     }
     ```
   - On user Decline or timeout:
     ```json
     {
       "status": "declined"
     }
     ```
4. **Authentication on Subsequent Requests**:
   - All other endpoints (except `/ping` and `/pair`) MUST include:
     - Header `X-Flik-Device-Id: <sender-device-id>`
     - Header `Authorization: Bearer <token>`
   - The receiver checks the token using constant-time comparison (`timingSafeEqual`). If the device is unknown or token is invalid, returns HTTP `401 Unauthorized`.

---

## 3. Endpoints

### `GET /ping`
- **Auth**: None
- **Response** (HTTP 200):
  ```json
  {
    "deviceId": "uuid",
    "deviceName": "string",
    "platform": "windows" | "android",
    "ver": 1,
    "freeBytes": 10485760000,
    "busy": false
  }
  ```

### `POST /pair`
- **Auth**: None
- **Request**: `{ deviceId, deviceName, platform, nonce }`
- **Response**: `{ status: "accepted" | "declined", token?: string }`

### `POST /transfer`
- **Auth**: Required (`X-Flik-Device-Id`, `Authorization: Bearer <token>`)
- **Content-Type**: `multipart/form-data`
- **Parts Order**:
  1. `meta`: JSON field conforming to `transfer-meta.schema.json`:
     ```json
     {
       "transferId": "string",
       "items": [
         {
           "name": "photo.jpg",
           "size": 1048576,
           "mime": "image/jpeg",
           "kind": "image" | "video" | "file"
         }
       ],
       "trajectoryX": 0.5
     }
     ```
  2. Sequential file parts matching the metadata items order.
- **Handling**:
  - Total size pre-check: If `freeBytes < totalDeclaredSize + 50MB`, return HTTP `507 Insufficient Storage`.
  - Concurrency check: If already actively receiving from another device, return HTTP `409 Conflict` with `{"error": "busy"}`.
  - Files are streamed directly to `<sanitizedName>.part`.
  - On stream complete and hash/length verification, renamed to `<sanitizedName>`.
  - On network interruption, timeout, or abort, partial files are deleted immediately.

### `POST /transfer/url`
- **Auth**: Required (`X-Flik-Device-Id`, `Authorization: Bearer <token>`)
- **Request**:
  ```json
  {
    "transferId": "string",
    "url": "https://example.com/article",
    "title": "Optional Title"
  }
  ```
- **Rules**:
  - Must begin with `http://` or `https://`.
  - Max length: 2048 characters.
  - Any other protocol scheme (`file:`, `javascript:`, `intent:`) returns HTTP `400 Bad Request`.

### `DELETE /transfer/:id`
- **Auth**: Required
- **Purpose**: Client cancellation. Receiver aborts active incoming streams for `transferId` and removes any pending `.part` files.
- **Response**: HTTP `200 OK` `{"status": "cancelled"}`.

---

## 4. Receiver Hardening Rules

1. **Watchdog**: 10-second inactivity watchdog on streaming connections. If zero bytes are received for 10s, abort stream, delete `.part` files, and reset state.
2. **Filename Sanitization**:
   - Strip path characters (`/`, `\`), `..`, null bytes, control characters.
   - Filter reserved Windows names (`CON`, `PRN`, `AUX`, `NUL`, `COM1-9`, `LPT1-9`).
   - Limit filename length to 128 characters (preserving extension).
   - Deduplicate if filename exists by appending ` (1)`, ` (2)`.
3. **Rate Limiting**: Rate limit unauthenticated `/pair` and `/ping` to max 10 requests per second per IP to prevent flood.
