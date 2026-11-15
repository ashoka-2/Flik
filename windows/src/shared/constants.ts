// Defines protocol constants, network timeouts, and normalized user-facing error messages.

export const FLIK_CONSTANTS = {
  SERVICE_TYPE: '_flik._tcp',
  PROTOCOL_VERSION: 1,
  DEFAULT_PORT: 54321,
  MAX_PORT: 54330,
  DISK_SAFETY_MARGIN_BYTES: 50 * 1024 * 1024, // 50MB
  WATCHDOG_IDLE_TIMEOUT_MS: 10000, // 10s
  PAIRING_TIMEOUT_MS: 30000, // 30s
  PING_TIMEOUT_MS: 800, // 800ms
  CONNECT_TIMEOUT_MS: 3000, // 3s
  TOAST_AUTO_DISMISS_MS: 3500, // 3.5s
  TOAST_DEDUPE_WINDOW_MS: 3000, // 3s
  MAX_URL_LENGTH: 2048,
  MAX_FILENAME_LENGTH: 128,
};

// Normalized error messages as mandated by section 6 of the Flik specification.
export const NORMALIZED_ERRORS = {
  PEER_UNREACHABLE: (device: string) => `Couldn't reach ${device}. Make sure both devices are on the same Wi-Fi or hotspot.`,
  TIMEOUT_OR_STALL: (device: string) => `Connection timed out. ${device} stopped responding. Try sending again.`,
  PAIRING_DECLINED: (device: string) => `${device} declined the connection request.`,
  RECEIVER_BUSY: (device: string) => `${device} is busy receiving another file. Try again in a moment.`,
  LOW_STORAGE_ANDROID: (device: string) => `Not enough storage space on ${device} to save this file.`,
  LOW_DISK_WINDOWS: () => `Not enough free disk space on this PC to save the incoming file.`,
  MISSING_FILE: () => `This file couldn't be read or was moved from your device.`,
  INVALID_URL_INPUT: () => `Please enter a valid web link starting with http:// or https://.`,
  UNSAFE_URL_RECEIVED: (device: string) => `Blocked an unsafe or invalid link from ${device}.`,
  TRANSFER_INTERRUPTED: (device: string) => `Transfer from ${device} was interrupted. Ask them to flick again.`,
  SAVE_FAILED: () => `Couldn't save file to that folder. Choose another folder or close open files.`,
  ALL_PORTS_BUSY: () => `Local network port is busy. Restart Flik Connector to reconnect.`,
};
