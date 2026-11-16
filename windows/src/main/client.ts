import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { FlikSettingsStore } from './store';

export async function sendFilesToPeer(
  peer: { ip: string; port: number; deviceId: string; deviceName?: string },
  filePaths: string[],
  store: FlikSettingsStore
): Promise<{ success: boolean; error?: string }> {
  try {
    const validFiles = filePaths.filter((p) => fs.existsSync(p));
    if (validFiles.length === 0) {
      return { success: false, error: 'No valid files selected' };
    }

    let token = store.getTrustedDevice(peer.deviceId)?.token;
    if (!token) {
      const allTrusted = store.getTrustedDevices();
      if (allTrusted.length > 0) {
        token = allTrusted[allTrusted.length - 1].token;
      }
    }
    if (!token) token = 'default';
    const formData = new FormData();
    const itemsMeta: { name: string; size: number; mime: string; kind: 'file' | 'image' | 'video' }[] = [];

    for (const fp of validFiles) {
      const stat = fs.statSync(fp);
      const name = path.basename(fp);
      const ext = path.extname(fp).toLowerCase();
      const isImg = ['.jpg', '.jpeg', '.png', '.webp', '.heic', '.gif'].includes(ext);
      const isVid = ['.mp4', '.mov', '.mkv', '.avi'].includes(ext);
      const kind = isImg ? 'image' : isVid ? 'video' : 'file';
      const mime = isImg ? `image/${ext.slice(1)}` : isVid ? `video/${ext.slice(1)}` : 'application/octet-stream';

      itemsMeta.push({ name, size: stat.size, mime, kind });
      const buffer = fs.readFileSync(fp);
      const blob = new Blob([buffer]);
      formData.append('files', blob, name);
    }

    formData.append(
      'meta',
      JSON.stringify({
        transferId: crypto.randomUUID(),
        items: itemsMeta,
      })
    );

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 60000); // 60s timeout

    const res = await fetch(`http://${peer.ip}:${peer.port}/transfer`, {
      method: 'POST',
      headers: {
        'X-Flik-Device-Id': store.getDeviceId(),
        Authorization: `Bearer ${token}`,
      },
      body: formData,
      signal: controller.signal,
    });
    clearTimeout(timeout);

    if (res.ok) {
      return { success: true };
    } else {
      const errText = await res.text().catch(() => '');
      return { success: false, error: `Transfer failed: ${res.status} ${errText}` };
    }
  } catch (err: any) {
    console.error('sendFilesToPeer error:', err);
    return { success: false, error: err?.message || 'Connection error' };
  }
}
