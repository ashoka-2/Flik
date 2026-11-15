// Automated integration test verifying full protocol interactions and edge cases.
// Run with: node tools/run-integration-tests.mjs

import { createFakePcReceiver } from './fake-pc-receiver.mjs';
import { runFakePhoneSender } from './fake-phone-sender.mjs';
import http from 'node:http';

async function main() {
  const testPort = 54325;
  console.log(`Starting mock receiver on port ${testPort}...`);
  const receiver = createFakePcReceiver(testPort);
  await receiver.start();

  try {
    // 1. Run full phone sender suite
    await runFakePhoneSender('127.0.0.1', testPort);

    // 2. Test Low Disk Space (507 Insufficient Storage)
    console.log('[Test] Simulating low disk space rejection (507)...');
    receiver.setSimulateLowDisk(true);
    const lowSpaceRes = await testMultipartDirect('127.0.0.1', testPort);
    if (lowSpaceRes.statusCode !== 507) {
      throw new Error(`Expected 507 Insufficient Storage, got ${lowSpaceRes.statusCode}`);
    }
    console.log('✓ Correctly rejected with 507 Insufficient Storage.');
    receiver.setSimulateLowDisk(false);

    // 3. Test Busy Receiver (409 Conflict)
    console.log('[Test] Simulating busy receiver rejection (409)...');
    receiver.setBusy(true);
    const busyRes = await testMultipartDirect('127.0.0.1', testPort);
    if (busyRes.statusCode !== 409) {
      throw new Error(`Expected 409 Conflict, got ${busyRes.statusCode}`);
    }
    console.log('✓ Correctly rejected with 409 Conflict (busy).');
    receiver.setBusy(false);

    console.log('\n=============================================');
    console.log('   ALL INTEGRATION TESTS PASSED WITH 0 ERRORS');
    console.log('=============================================\n');
  } finally {
    await receiver.stop();
    console.log('Receiver stopped cleanly.');
  }
}

function testMultipartDirect(host, port) {
  return new Promise((resolve, reject) => {
    // First pair to get token
    const pairData = JSON.stringify({ deviceId: 'test-direct', deviceName: 'Direct Test', platform: 'android', nonce: '1234567890123456' });
    const req = http.request(
      {
        hostname: host,
        port,
        path: '/pair',
        method: 'POST',
        headers: { 'content-type': 'application/json', 'content-length': pairData.length },
      },
      (res) => {
        let body = '';
        res.on('data', (c) => (body += c));
        res.on('end', () => {
          const { token } = JSON.parse(body);
          // Send transfer
          const xferReq = http.request(
            {
              hostname: host,
              port,
              path: '/transfer',
              method: 'POST',
              headers: {
                'x-flik-device-id': 'test-direct',
                'authorization': `Bearer ${token}`,
                'content-type': 'multipart/form-data',
              },
            },
            (xferRes) => {
              resolve({ statusCode: xferRes.statusCode });
            }
          );
          xferReq.on('error', reject);
          xferReq.write('dummy');
          xferReq.end();
        });
      }
    );
    req.on('error', reject);
    req.write(pairData);
    req.end();
  });
}

main().catch((err) => {
  console.error('Integration test failed:', err);
  process.exit(1);
});
