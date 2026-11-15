// Simulates a Windows Flik Connector PC receiver to verify Android sender logic.

import http from 'node:http';
import crypto from 'node:crypto';
import { derivePairingCode } from './verify-protocol.mjs';

export function createFakePcReceiver(port = 54321) {
  const pairedTokens = new Map();
  let isBusy = false;
  let simulateLowDisk = false;

  const server = http.createServer(async (req, res) => {
    const u = new URL(req.url, `http://localhost:${port}`);

    // GET /ping
    if (req.method === 'GET' && u.pathname === '/ping') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(
        JSON.stringify({
          deviceId: 'fake-pc-receiver-001',
          deviceName: 'Windows-PC (Mock)',
          platform: 'windows',
          ver: 1,
          freeBytes: simulateLowDisk ? 1024 : 42949672960,
          busy: isBusy,
        })
      );
      return;
    }

    // POST /pair
    if (req.method === 'POST' && u.pathname === '/pair') {
      let body = '';
      req.on('data', (c) => (body += c));
      req.on('end', () => {
        try {
          const data = JSON.parse(body);
          const token = crypto.randomBytes(32).toString('hex');
          pairedTokens.set(data.deviceId, token);
          res.writeHead(200, { 'content-type': 'application/json' });
          res.end(JSON.stringify({ status: 'accepted', token }));
        } catch {
          res.writeHead(400);
          res.end(JSON.stringify({ error: 'Malformed JSON' }));
        }
      });
      return;
    }

    // Authenticate subsequent routes
    const senderId = req.headers['x-flik-device-id'];
    const authHeader = req.headers['authorization'];
    if (!senderId || !authHeader || !authHeader.startsWith('Bearer ')) {
      res.writeHead(401, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: 'Unauthorized' }));
      return;
    }

    const token = authHeader.slice(7).trim();
    if (pairedTokens.get(senderId) !== token) {
      res.writeHead(401, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: 'Invalid token' }));
      return;
    }

    // POST /transfer
    if (req.method === 'POST' && u.pathname === '/transfer') {
      if (simulateLowDisk) {
        res.writeHead(507, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ error: 'Insufficient disk space' }));
        return;
      }
      if (isBusy) {
        res.writeHead(409, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ error: 'busy' }));
        return;
      }

      req.on('data', () => {});
      req.on('end', () => {
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ status: 'completed' }));
      });
      return;
    }

    // POST /transfer/url
    if (req.method === 'POST' && u.pathname === '/transfer/url') {
      let body = '';
      req.on('data', (c) => (body += c));
      req.on('end', () => {
        try {
          const data = JSON.parse(body);
          if (!data.url || !data.url.startsWith('http')) {
            res.writeHead(400, { 'content-type': 'application/json' });
            res.end(JSON.stringify({ error: 'Invalid URL' }));
            return;
          }
          res.writeHead(200, { 'content-type': 'application/json' });
          res.end(JSON.stringify({ status: 'opened' }));
        } catch {
          res.writeHead(400);
          res.end(JSON.stringify({ error: 'Malformed JSON' }));
        }
      });
      return;
    }

    res.writeHead(404);
    res.end();
  });

  return {
    server,
    start: () => new Promise((resolve) => server.listen(port, resolve)),
    stop: () => new Promise((resolve) => server.close(resolve)),
    setBusy: (val) => (isBusy = val),
    setSimulateLowDisk: (val) => (simulateLowDisk = val),
  };
}

if (process.argv[1].endsWith('fake-pc-receiver.mjs')) {
  const receiver = createFakePcReceiver(54321);
  receiver.start().then(() => {
    console.log('Fake PC Receiver listening on port 54321');
  });
}
