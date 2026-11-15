// Provides cryptographic functions for Flik pairing, token verification, and code generation.

import crypto from 'crypto';

/**
 * Derives a deterministic 4-digit confirmation code from a pairing nonce.
 * Algorithm: (SHA-256(nonce)[0..3] as uint % 9000) + 1000
 */
export function derivePairingCode(nonce: string): string {
  const hash = crypto.createHash('sha256').update(nonce).digest();
  const num = hash.readUInt32BE(0);
  return String((num % 9000) + 1000);
}

/**
 * Generates a cryptographically secure 32-byte authentication token (64 hex characters).
 */
export function generateAuthToken(): string {
  return crypto.randomBytes(32).toString('hex');
}

/**
 * Generates a random nonce for pairing initiation (at least 16 bytes).
 */
export function generateNonce(): string {
  return crypto.randomBytes(16).toString('hex');
}

/**
 * Compares two authentication tokens in constant time to prevent timing attacks.
 */
export function constantTimeCompare(a: string, b: string): boolean {
  if (!a || !b || typeof a !== 'string' || typeof b !== 'string') {
    return false;
  }
  const bufA = Buffer.from(a, 'utf8');
  const bufB = Buffer.from(b, 'utf8');
  if (bufA.length !== bufB.length) {
    return false;
  }
  return crypto.timingSafeEqual(bufA, bufB);
}
