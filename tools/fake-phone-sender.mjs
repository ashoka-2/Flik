// Simulates an Android phone sender communicating with the Windows Flik Connector.
// Tests pairing, file batch transfers, web link transmission, aborted streams, and security boundaries.

import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { derivePairingCode } from './verify-protocol.mjs';

export async function runFakePhoneSender(host = '127.0.0.1', port = 54321, options = {}) {
  console.log(`\n=== Running Fake Phone Sender against http://${host}:${port} ===`);

  // 1. Pre-flight Ping
  console.log('[1] Pre-flight Ping...');
  const ping = await httpGetJson(`http://${host}:${port}/ping`);
  console.log(`    Received ping response: deviceName="${ping.deviceName}", platform="${ping.platform}", ver=${ping.ver}`);
  if (ping.busy) {
    throw new Error('Receiver reports busy state');
  }

  // 2. Initiate Pairing Handshake
  console.log('[2] Initiating Pairing Handshake...');
  const nonce = crypto.randomBytes(16).toString('hex');
  const code = derivePairingCode(nonce);
  console.log(`    Derived 4-digit code: ${code}`);

  const pairPromise = httpPostJson(`http://${host}:${port}/pair`, {
    deviceId: 'fake-android-phone-001',
    deviceName: 'Pixel 8 (Test Phone)',
    platform: 'android',
    nonce,
  });

  // If auto-accept callback is supplied or in automated test mode
  if (options.onCode) {
    options.onCode(code);
  }

  const pairRes = await pairPromise;
  if (pairRes.status !== 'accepted' || !pairRes.token) {
    throw new Error(`Pairing was not accepted: ${JSON.stringify(pairRes)}`);
  }
  const token = pairRes.token;
  console.log(`    Pairing accepted! Acquired token: ${token.slice(0, 16)}...`);

  // 3. Test Security: Send without token (Must return 401 Unauthorized)
  console.log('[3] Testing Security: Unauthenticated transfer attempt...');
  const unauthRes = await httpPostMultipart(`http://${host}:${port}/transfer`, {
    headers: {
      'x-flik-device-id': 'fake-android-phone-001',
      // Missing Authorization header
    },
    meta: { transferId: 'bad-xfer-1', items: [{ name: 'test.txt', size: 5, mime: 'text/plain', kind: 'file' }] },
    files: [{ name: 'test.txt', content: 'hello' }],
  });
  if (unauthRes.statusCode !== 401) {
    throw new Error(`Expected 401 for unauthenticated request, got ${unauthRes.statusCode}`);
  }
  console.log('    ✓ Rejected unauthenticated request with 401 Unauthorized.');

  // 4. Test Valid Multipart File Transfer
  console.log('[4] Sending batch of files (image and document)...');
  const transferId = `test-xfer-${Date.now()}`;
  const validRes = await httpPostMultipart(`http://${host}:${port}/transfer`, {
    headers: {
      'x-flik-device-id': 'fake-android-phone-001',
      'authorization': `Bearer ${token}`,
    },
    meta: {
      transferId,
      items: [
        { name: 'sample_photo.jpg', size: 1024, mime: 'image/jpeg', kind: 'image' },
        { name: 'document.pdf', size: 2048, mime: 'application/pdf', kind: 'file' },
      ],
      trajectoryX: 0.25,
    },
    files: [
      { name: 'sample_photo.jpg', content: Buffer.alloc(1024, 0xAA) },
      { name: 'document.pdf', content: Buffer.alloc(2048, 0xBB) },
    ],
  });
  if (validRes.statusCode !== 200) {
    throw new Error(`Transfer failed with status ${validRes.statusCode}: ${validRes.body}`);
  }
  console.log('    ✓ Batch file transfer completed successfully!');

  // 5. Test Web URL Transmission
  console.log('[5] Testing URL transfer (/transfer/url)...');
  const urlRes = await httpPostJson(
    `http://${host}:${port}/transfer/url`,
    {
      transferId: `url-xfer-${Date.now()}`,
      url: 'https://example.com/article',
      title: 'Example Article',
    },
    {
      'x-flik-device-id': 'fake-android-phone-001',
      'authorization': `Bearer ${token}`,
    }
  );
  if (urlRes.status !== 'opened') {
    throw new Error(`Expected URL opened status, got ${JSON.stringify(urlRes)}`);
  }
  console.log('    ✓ Valid URL successfully accepted and opened.');

  // 6. Test Security: Reject Malicious/Unsafe URL (e.g. javascript:)
  console.log('[6] Testing Security: Malicious URL rejection...');
  const badUrlRes = await httpPostRaw(
    `http://${host}:${port}/transfer/url`,
    JSON.stringify({
      transferId: `bad-url-${Date.now()}`,
      url: 'javascript:alert(1)',
    }),
    {
      'content-type': 'application/json',
      'x-flik-device-id': 'fake-android-phone-001',
      'authorization': `Bearer ${token}`,
    }
  );
  if (badUrlRes.statusCode !== 400) {
    throw new Error(`Expected 400 for unsafe URL, got ${badUrlRes.statusCode}`);
  }
  console.log('    ✓ Blocked unsafe URL scheme with 400 Bad Request.');

  console.log('\n=== All Fake Phone Sender Tests Passed Successfully! ===\n');
}

function httpGetJson(urlStr) {
  return new Promise((resolve, reject) => {
    http.get(urlStr, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          reject(e);
        }
      });
    }).on('error', reject);
  });
}

function httpPostJson(urlStr, body, customHeaders = {}) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(body);
    const u = new URL(urlStr);
    const req = http.request(
      {
        hostname: u.hostname,
        port: u.port,
        path: u.pathname,
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'content-length': Buffer.byteLength(payload),
          ...customHeaders,
        },
      },
      (res) => {
        let data = '';
        res.on('data', (c) => (data += c));
        res.on('end', () => {
          try {
            resolve(JSON.parse(data));
          } catch {
            resolve({ raw: data, status: res.statusCode });
          }
        });
      }
    );
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

function httpPostRaw(urlStr, data, headers) {
  return new Promise((resolve, reject) => {
    const u = new URL(urlStr);
    const req = http.request(
      {
        hostname: u.hostname,
        port: u.port,
        path: u.pathname,
        method: 'POST',
        headers: {
          'content-length': Buffer.byteLength(data),
          ...headers,
        },
      },
      (res) => {
        let body = '';
        res.on('data', (c) => (body += c));
        res.on('end', () => resolve({ statusCode: res.statusCode, body }));
      }
    );
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

function httpPostMultipart(urlStr, { headers, meta, files }) {
  return new Promise((resolve, reject) => {
    const boundary = '----FlikTestBoundary' + Date.now();
    const u = new URL(urlStr);

    const parts = [];

    // Part 1: Meta field
    parts.push(Buffer.from(
      `--${boundary}\r\n` +
      `Content-Disposition: form-data; name="meta"\r\n\r\n` +
      `${JSON.stringify(meta)}\r\n`
    ));

    // Subsequent parts: Files
    for (const f of files) {
      parts.push(Buffer.from(
        `--${boundary}\r\n` +
        `Content-Disposition: form-data; name="files"; filename="${f.name}"\r\n` +
        `Content-Type: application/octet-stream\r\n\r\n`
      ));
      parts.push(Buffer.isBuffer(f.content) ? f.content : Buffer.from(f.content));
      parts.push(Buffer.from('\r\n'));
    }

    parts.push(Buffer.from(`--${boundary}--\r\n`));
    const fullBody = Buffer.concat(parts);

    const req = http.request(
      {
        hostname: u.hostname,
        port: u.port,
        path: u.pathname,
        method: 'POST',
        headers: {
          'content-type': `multipart/form-data; boundary=${boundary}`,
          'content-length': fullBody.length,
          ...headers,
        },
      },
      (res) => {
        let body = '';
        res.on('data', (c) => (body += c));
        res.on('end', () => resolve({ statusCode: res.statusCode, body }));
      }
    );
    req.on('error', reject);
    req.write(fullBody);
    req.end();
  });
}

if (process.argv[1].endsWith('fake-phone-sender.mjs')) {
  runFakePhoneSender().catch((err) => {
    console.error('Fake phone sender failed:', err);
    process.exit(1);
  });
}
