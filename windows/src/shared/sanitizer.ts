// Provides security sanitization for incoming filenames and URL allowlist enforcement.

import path from 'path';
import { FLIK_CONSTANTS } from './constants';

const WINDOWS_RESERVED_NAMES = /^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$/i;

/**
 * Sanitizes an incoming client filename to prevent directory traversal, control characters,
 * or invalid Windows filenames.
 */
export function sanitizeFilename(rawName: string): string {
  if (!rawName || typeof rawName !== 'string') {
    return `flik-file-${Date.now()}`;
  }

  // Remove directory separators, null bytes, and traversal elements
  let clean = rawName
    .replace(/[/\\]/g, '_')
    .replace(/\0/g, '')
    .replace(/\.\.+/g, '.')
    // Remove control characters (0x00 - 0x1F) and Windows illegal characters (< > : " / \ | ? *)
    .replace(/[\x00-\x1F<>:"/\\|?*]/g, '_')
    .trim();

  // If filename is empty or dots only
  if (!clean || /^[\s.]+$/.test(clean)) {
    clean = `flik-item-${Date.now()}`;
  }

  // Check reserved Windows names
  if (WINDOWS_RESERVED_NAMES.test(clean)) {
    clean = `flik_${clean}`;
  }

  // Cap length to max 128 characters while preserving file extension
  if (clean.length > FLIK_CONSTANTS.MAX_FILENAME_LENGTH) {
    const ext = path.extname(clean);
    const base = path.basename(clean, ext);
    const maxBaseLen = Math.max(1, FLIK_CONSTANTS.MAX_FILENAME_LENGTH - ext.length);
    clean = base.slice(0, maxBaseLen) + ext;
  }

  return clean;
}

/**
 * Validates an incoming URL against the strict HTTP/HTTPS allowlist and length limit.
 * Rejects javascript:, file:, data:, intent: schemes.
 */
export function validateUrl(rawUrl: string): { valid: boolean; normalized?: string; error?: string } {
  if (!rawUrl || typeof rawUrl !== 'string') {
    return { valid: false, error: 'Empty URL' };
  }

  if (rawUrl.length > FLIK_CONSTANTS.MAX_URL_LENGTH) {
    return { valid: false, error: 'URL exceeds maximum length of 2048 characters' };
  }

  try {
    const parsed = new URL(rawUrl);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return { valid: false, error: 'Only http: and https: protocols are permitted' };
    }
    return { valid: true, normalized: parsed.toString() };
  } catch {
    return { valid: false, error: 'Malformed URL' };
  }
}
