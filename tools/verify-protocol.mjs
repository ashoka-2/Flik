// Validates Flik protocol schemas and test vectors.
// Run with: node tools/verify-protocol.mjs

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');
const protocolDir = path.join(rootDir, 'protocol');
const fixturesDir = path.join(protocolDir, 'fixtures');

/**
 * Derives the 4-digit pairing confirmation code from a nonce.
 * Algorithm: (SHA-256(nonce)[0..3] as uint % 9000) + 1000
 */
export function derivePairingCode(nonce) {
  const hash = crypto.createHash('sha256').update(nonce).digest();
  const num = hash.readUInt32BE(0);
  return String((num % 9000) + 1000);
}

/**
 * Validates basic object structure according to the protocol rules.
 */
function validateFixtures() {
  console.log('Verifying Flik protocol specifications and test vectors...');

  // 1. Verify pairing code derivation
  const testNonce = 'c9a4f6d8e2b1a03f47e58912d0a3bc76';
  const code = derivePairingCode(testNonce);
  if (!/^\d{4}$/.test(code)) {
    throw new Error(`Invalid derived pairing code: ${code}`);
  }
  console.log(`✓ Pairing code derivation test: nonce=${testNonce.slice(0, 8)}... -> code=${code}`);

  // 2. Validate transfer-meta fixture
  const meta = JSON.parse(fs.readFileSync(path.join(fixturesDir, 'transfer-meta.valid.json'), 'utf8'));
  if (!meta.transferId || !Array.isArray(meta.items) || meta.items.length === 0) {
    throw new Error('Invalid transfer-meta fixture');
  }
  for (const item of meta.items) {
    if (!item.name || typeof item.size !== 'number' || !item.mime || !['file', 'image', 'video'].includes(item.kind)) {
      throw new Error(`Invalid item in transfer-meta: ${JSON.stringify(item)}`);
    }
  }
  console.log('✓ Validated transfer-meta fixture');

  // 3. Validate pair-request fixture
  const pairReq = JSON.parse(fs.readFileSync(path.join(fixturesDir, 'pair-request.valid.json'), 'utf8'));
  if (!pairReq.deviceId || !pairReq.deviceName || !['android', 'windows'].includes(pairReq.platform) || pairReq.nonce.length < 16) {
    throw new Error('Invalid pair-request fixture');
  }
  console.log('✓ Validated pair-request fixture');

  // 4. Validate pair-response fixture
  const pairRes = JSON.parse(fs.readFileSync(path.join(fixturesDir, 'pair-response.valid.json'), 'utf8'));
  if (!['accepted', 'declined'].includes(pairRes.status) || (pairRes.status === 'accepted' && !pairRes.token)) {
    throw new Error('Invalid pair-response fixture');
  }
  console.log('✓ Validated pair-response fixture');

  // 5. Validate ping-response fixture
  const pingRes = JSON.parse(fs.readFileSync(path.join(fixturesDir, 'ping-response.valid.json'), 'utf8'));
  if (!pingRes.deviceId || !pingRes.deviceName || typeof pingRes.ver !== 'number' || typeof pingRes.freeBytes !== 'number' || typeof pingRes.busy !== 'boolean') {
    throw new Error('Invalid ping-response fixture');
  }
  console.log('✓ Validated ping-response fixture');

  // 6. Validate url-transfer fixture
  const urlXfer = JSON.parse(fs.readFileSync(path.join(fixturesDir, 'url-transfer.valid.json'), 'utf8'));
  if (!urlXfer.transferId || !urlXfer.url || !/^https?:\/\//i.test(urlXfer.url) || urlXfer.url.length > 2048) {
    throw new Error('Invalid url-transfer fixture');
  }
  console.log('✓ Validated url-transfer fixture');

  console.log('All protocol schemas and test vectors verified successfully.');
}

validateFixtures();
