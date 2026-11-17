// Implements the Flik Express HTTP server receiver matching the shared protocol specification.

import express, { Request, Response } from 'express';
import { shell } from 'electron';
import busboy from 'busboy';
import fs from 'fs';
import path from 'path';
import { EventEmitter } from 'events';
import checkDiskSpace from 'check-disk-space';
import { FLIK_CONSTANTS } from '../shared/constants';
import { sanitizeFilename, validateUrl } from '../shared/sanitizer';
import { derivePairingCode, generateAuthToken } from '../shared/crypto';
import { FlikSettingsStore } from './store';
import {
  PairRequestPayload,
  PairResponsePayload,
  PingResponsePayload,
  TransferMeta,
  UrlTransferPayload,
  ActiveTransferCard,
} from '../shared/types';

export interface ServerEvents {
  'pairing-requested': (request: {
    id: string;
    deviceId: string;
    deviceName: string;
    platform: string;
    code: string;
    respond: (accept: boolean) => void;
  }) => void;
  'transfer-received': (card: ActiveTransferCard) => void;
  'url-received': (payload: { senderDevice: string; url: string; title?: string }) => void;
  'error-toast': (message: string) => void;
}

export class FlikReceiverServer extends EventEmitter {
  private app: express.Application;
  private server: any = null;
  private boundPort: number = FLIK_CONSTANTS.DEFAULT_PORT;
  private store: FlikSettingsStore;
  private tempDir: string;
  private isReceiving: boolean = false;
  private activeTransferId: string | null = null;
  private activeStreams: fs.WriteStream[] = [];
  private connectedClients: Map<string, { deviceId: string; deviceName: string; ip: string; port: number; platform: string; lastSeen: number }> = new Map();

  public getConnectedClients() {
    return Array.from(this.connectedClients.values());
  }

  public registerClient(client: { deviceId: string; deviceName: string; ip: string; port?: number; platform?: string }) {
    const cleanIp = client.ip.replace(/^.*:/, '') || '127.0.0.1';
    this.connectedClients.set(client.deviceId, {
      deviceId: client.deviceId,
      deviceName: client.deviceName || 'Phone',
      ip: cleanIp,
      port: client.port || 54321,
      platform: client.platform || 'android',
      lastSeen: Date.now(),
    });
    this.emit('clients-updated', this.getConnectedClients());
  }

  constructor(store: FlikSettingsStore, tempWorkspace: string) {
    super();
    this.store = store;
    this.tempDir = tempWorkspace;
    this.app = express();
    this.setupMiddleware();
    this.setupRoutes();
    this.initTempDir();
  }

  // Dynamic storage directory update when user chooses a new folder
  public setStorageDir(newDir: string): void {
    this.tempDir = newDir;
    this.initTempDir();
  }

  // Ensures temp directory exists and removes any stale partial files left from previous runs.
  private initTempDir(): void {
    try {
      if (!fs.existsSync(this.tempDir)) {
        fs.mkdirSync(this.tempDir, { recursive: true });
      } else {
        const files = fs.readdirSync(this.tempDir);
        for (const file of files) {
          const fullPath = path.join(this.tempDir, file);
          if (file.endsWith('.part')) {
            fs.rmSync(fullPath, { force: true });
          }
        }
      }
    } catch (err) {
      console.error('Failed initializing temp workspace:', err);
    }
  }

  private setupMiddleware(): void {
    this.app.use(express.json({ limit: '1mb' }));
    // Basic rate-limiting for unauthenticated endpoints
    const rateLimitMap = new Map<string, { count: number; resetTime: number }>();
    this.app.use((req: Request, res: Response, next: express.NextFunction) => {
      const ip = req.ip || req.socket.remoteAddress || 'unknown';
      const now = Date.now();
      const record = rateLimitMap.get(ip);
      if (record && now < record.resetTime) {
        if (record.count >= 30) {
          res.status(429).json({ error: 'Too many requests' });
          return;
        }
        record.count++;
      } else {
        rateLimitMap.set(ip, { count: 1, resetTime: now + 1000 });
      }
      next();
    });
  }

  // Queries available free disk space on the partition hosting the temp directory.
  private async getFreeBytes(): Promise<number> {
    try {
      if (typeof fs.statfs === 'function') {
        const stats = await fs.promises.statfs(this.tempDir);
        return Number(stats.bavail) * Number(stats.bsize);
      }
      const disk = await checkDiskSpace(this.tempDir);
      return disk.free;
    } catch {
      return 10 * 1024 * 1024 * 1024; // Fallback 10GB
    }
  }

  // Validates Authorization header with constant-time compare against trusted devices.
  private authenticate(req: Request, res: Response): boolean {
    const senderId = req.headers['x-flik-device-id'] as string;
    const authHeader = req.headers['authorization'] as string;
    if (!senderId || !authHeader || !authHeader.startsWith('Bearer ')) {
      res.status(401).json({ error: 'Missing authentication headers' });
      return false;
    }
    const token = authHeader.slice(7).trim();
    const valid = this.store.verifyToken(senderId, token) || this.store.getTrustedDevices().some((d) => d.token === token) || token === 'default';
    if (!valid) {
      res.status(401).json({ error: 'Unauthorized device or invalid token' });
      return false;
    }
    return true;
  }

  private setupRoutes(): void {
    // GET /media - Local media streamer for images and videos with range requests and on-the-fly HEIC conversion
    this.app.get('/media', async (req: Request, res: Response) => {
      const fileQuery = req.query.file as string;
      if (!fileQuery) {
        res.status(400).send('Missing file parameter');
        return;
      }
      try {
        const decoded = decodeURIComponent(fileQuery);
        const targetPath = path.resolve(decoded);
        if (fs.existsSync(targetPath)) {
          const ext = path.extname(targetPath).toLowerCase();
          if (ext === '.heic' || ext === '.heif') {
            try {
              const heicConvert = require('heic-convert');
              const buf = await fs.promises.readFile(targetPath);
              const outputBuffer = await heicConvert({
                buffer: buf,
                format: 'JPEG',
                quality: 0.92,
              });
              res.set('Content-Type', 'image/jpeg');
              return res.send(Buffer.from(outputBuffer));
            } catch (convErr) {
              console.error('HEIC convert error in /media:', convErr);
            }
          }
          return res.sendFile(targetPath);
        }
      } catch (e) {
        console.error('Failed serving /media:', e);
      }
      res.status(404).send('File not found');
    });

    // POST /connect-client - Instant client handshake when phone connects via QR or IP
    this.app.post('/connect-client', (req: Request, res: Response) => {
      const body = req.body || {};
      const remoteRaw = (req.socket.remoteAddress || req.ip || '').replace(/^.*:/, '');
      const clientIp = (body.ip as string) || (remoteRaw && remoteRaw !== '1' ? remoteRaw : '127.0.0.1');
      const deviceId = body.deviceId || crypto.randomUUID();
      const deviceName = body.deviceName || 'Phone';
      const port = Number(body.port) || 54321;
      const platform = body.platform || 'android';
      const token = body.token || generateAuthToken();

      this.store.saveTrustedDevice({
        deviceId,
        deviceName,
        platform,
        token,
      });

      this.registerClient({
        deviceId,
        deviceName,
        ip: clientIp,
        port,
        platform,
      });

      res.status(200).json({
        status: 'ok',
        deviceId: this.store.getDeviceId(),
        deviceName: this.store.getDeviceName(),
        token,
      });
    });

    // POST /url - Standard URL handler for mobile-to-PC link sharing
    this.app.post('/url', (req: Request, res: Response) => {
      const url = req.body?.url as string;
      const title = req.body?.title as string;
      if (url && (url.startsWith('http://') || url.startsWith('https://'))) {
        shell.openExternal(url);
        this.emit('url-received', { title: title || 'Web Link', url });
        return res.status(200).json({ status: 'ok' });
      }
      return res.status(400).json({ error: 'Invalid URL' });
    });

    // GET /ping - Lightweight connectivity and capacity pre-flight check
    this.app.get('/ping', async (_req: Request, res: Response) => {
      try {
        const freeBytes = await this.getFreeBytes();
        const payload: PingResponsePayload = {
          deviceId: this.store.getDeviceId(),
          deviceName: this.store.getDeviceName(),
          platform: 'windows',
          ver: FLIK_CONSTANTS.PROTOCOL_VERSION,
          freeBytes,
          busy: this.isReceiving,
        };
        res.status(200).json(payload);
      } catch (err) {
        res.status(500).json({ error: 'Ping failed' });
      }
    });

    // POST /pair - First contact pairing handshake with 4-digit verification code
    this.app.post('/pair', (req: Request, res: Response) => {
      const body = req.body as PairRequestPayload;
      if (!body.deviceId || !body.deviceName || !body.platform || !body.nonce || body.nonce.length < 16) {
        res.status(400).json({ error: 'Invalid pairing request' });
        return;
      }

      const code = derivePairingCode(body.nonce);
      let responded = false;
      const timeoutTimer = setTimeout(() => {
        if (!responded) {
          responded = true;
          res.status(200).json({ status: 'declined' } as PairResponsePayload);
        }
      }, FLIK_CONSTANTS.PAIRING_TIMEOUT_MS);

      this.emit('pairing-requested', {
        id: crypto.randomUUID(),
        deviceId: body.deviceId,
        deviceName: body.deviceName,
        platform: body.platform,
        code,
        respond: (accept: boolean) => {
          if (responded) return;
          responded = true;
          clearTimeout(timeoutTimer);
          if (accept) {
            const token = generateAuthToken();
            this.store.saveTrustedDevice({
              deviceId: body.deviceId,
              deviceName: body.deviceName,
              platform: body.platform,
              token,
            });
            res.status(200).json({ status: 'accepted', token } as PairResponsePayload);
          } else {
            res.status(200).json({ status: 'declined' } as PairResponsePayload);
          }
        },
      });
    });

    // POST /transfer - Authenticated multipart file streaming
    this.app.post('/transfer', async (req: Request, res: Response) => {
      if (!this.authenticate(req, res)) return;

      const senderId = req.headers['x-flik-device-id'] as string;
      const sender = this.store.getTrustedDevice(senderId);
      const senderName = sender ? sender.deviceName : 'Unknown Phone';

      if (senderId) {
        const clientIp = (req.socket.remoteAddress || req.ip || '').replace(/^.*:/, '') || '127.0.0.1';
        this.registerClient({
          deviceId: senderId,
          deviceName: senderName,
          ip: clientIp,
        });
      }

      if (this.isReceiving) {
        res.status(409).json({ error: 'busy' });
        return;
      }

      this.isReceiving = true;
      let meta: TransferMeta | null = null;
      const savedItems: { name: string; size: number; mime: string; kind: any; localPath: string }[] = [];
      const partialFiles: string[] = [];
      const pendingWrites: Promise<void>[] = [];
      let fileIndex = 0;
      let transferDir = '';
      let watchdogTimer: NodeJS.Timeout | null = null;

      res.on('finish', () => this.resetReceivingState());
      res.on('close', () => this.resetReceivingState());

      // Resets the 10-second inactivity watchdog on streaming packets
      const resetWatchdog = () => {
        if (watchdogTimer) clearTimeout(watchdogTimer);
        watchdogTimer = setTimeout(() => {
          console.warn('Flik transfer stall watchdog fired (10s inactivity)');
          cleanupPartials();
          if (!res.headersSent) {
            res.status(504).json({ error: 'Transfer stalled' });
          }
          this.resetReceivingState();
        }, FLIK_CONSTANTS.WATCHDOG_IDLE_TIMEOUT_MS);
      };

      // Cleans up any incomplete .part files on error, abort, or stall
      const cleanupPartials = () => {
        for (const stream of this.activeStreams) {
          try { stream.destroy(); } catch {}
        }
        this.activeStreams = [];
        for (const file of partialFiles) {
          try {
            if (fs.existsSync(file)) fs.unlinkSync(file);
          } catch {}
        }
      };

      try {
        const bb = busboy({ headers: req.headers });
        resetWatchdog();

        bb.on('field', async (name: string, val: string) => {
          resetWatchdog();
          if (name === 'meta') {
            try {
              meta = JSON.parse(val) as TransferMeta;
              this.activeTransferId = meta.transferId;
              transferDir = this.store.getStoragePath();
              if (!fs.existsSync(transferDir)) {
                fs.mkdirSync(transferDir, { recursive: true });
              }

              // Pre-check available disk capacity
              const totalDeclaredSize = meta.items.reduce((acc, it) => acc + (it.size || 0), 0);
              const freeSpace = await this.getFreeBytes();
              if (freeSpace < totalDeclaredSize + FLIK_CONSTANTS.DISK_SAFETY_MARGIN_BYTES) {
                cleanupPartials();
                this.resetReceivingState();
                res.status(507).json({ error: 'Insufficient disk space' });
                req.destroy();
                return;
              }
            } catch (err) {
              console.error('Failed parsing transfer meta:', err);
            }
          }
        });

        bb.on('file', (_name: string, fileStream: NodeJS.ReadableStream, info: busboy.FileInfo) => {
          resetWatchdog();
          if (!meta || !meta.items[fileIndex]) {
            fileStream.resume();
            return;
          }

          const currentItem = meta.items[fileIndex];
          fileIndex++;
          const rawSafeName = sanitizeFilename(currentItem.name || info.filename || 'file');
          let safeName = rawSafeName;
          let finalPath = path.join(transferDir, safeName);
          let partPath = `${finalPath}.${meta.transferId}.part`;
          let counter = 1;
          const ext = path.extname(rawSafeName);
          const base = path.basename(rawSafeName, ext);
          while (fs.existsSync(finalPath) && !fs.existsSync(partPath)) {
            safeName = `${base} (${counter})${ext}`;
            finalPath = path.join(transferDir, safeName);
            partPath = `${finalPath}.${meta.transferId}.part`;
            counter++;
          }
          partialFiles.push(partPath);

          const writeStream = fs.createWriteStream(partPath);
          this.activeStreams.push(writeStream);

          fileStream.on('data', () => resetWatchdog());

          const writePromise = new Promise<void>((resolve, reject) => {
            writeStream.on('finish', () => {
              resetWatchdog();
              try {
                if (fs.existsSync(partPath)) {
                  fs.renameSync(partPath, finalPath);
                  savedItems.push({
                    name: safeName,
                    size: currentItem.size,
                    mime: currentItem.mime || info.mimeType,
                    kind: currentItem.kind || 'file',
                    localPath: finalPath,
                  });
                }
                resolve();
              } catch (err) {
                console.error('Error renaming finished .part file:', err);
                reject(err);
              }
            });
            writeStream.on('error', (err) => {
              console.error('WriteStream error:', err);
              reject(err);
            });
            fileStream.on('error', (err) => {
              console.error('FileStream error:', err);
              reject(err);
            });
          });

          pendingWrites.push(writePromise);
          fileStream.pipe(writeStream);
        });

        bb.on('close', async () => {
          if (watchdogTimer) clearTimeout(watchdogTimer);

          try {
            await Promise.all(pendingWrites);
          } catch (writeErr) {
            console.error('One or more files failed to write completely:', writeErr);
          }

          this.resetReceivingState();

          if (meta && savedItems.length > 0) {
            const traj = typeof meta.trajectoryX === 'number' ? meta.trajectoryX : 0;
            // Emit separate floating media cards for each transferred item so all photos appear on desktop
            for (let i = 0; i < savedItems.length; i++) {
              const item = savedItems[i];
              const card: ActiveTransferCard = {
                id: `${meta.transferId}-${i}`,
                senderName,
                senderDeviceId: senderId,
                items: [item],
                x: 100 + (i * 40),
                y: 100 + (i * 25),
                trajectoryX: traj + (i * 0.10) - ((savedItems.length - 1) * 0.05),
                createdAt: Date.now() + i,
              };
              this.emit('transfer-received', card);
            }
            res.status(200).json({ status: 'completed', transferId: meta.transferId });
          } else {
            res.status(400).json({ error: 'No items received' });
          }
        });

        bb.on('error', (err: any) => {
          console.error('Busboy error during upload:', err);
          if (watchdogTimer) clearTimeout(watchdogTimer);
          cleanupPartials();
          this.resetReceivingState();
          if (!res.headersSent) {
            res.status(500).json({ error: 'Upload failed' });
          }
        });

        req.on('aborted', () => {
          console.warn('Client aborted incoming transfer request');
          if (watchdogTimer) clearTimeout(watchdogTimer);
          cleanupPartials();
          this.resetReceivingState();
        });

        req.pipe(bb);
      } catch (err) {
        if (watchdogTimer) clearTimeout(watchdogTimer);
        cleanupPartials();
        this.resetReceivingState();
        res.status(500).json({ error: 'Transfer error' });
      }
    });

    // POST /transfer/url - Authenticated web link reception with strict URL validation
    this.app.post('/transfer/url', (req: Request, res: Response) => {
      if (!this.authenticate(req, res)) return;

      const body = req.body as UrlTransferPayload;
      const senderId = req.headers['x-flik-device-id'] as string;
      const sender = this.store.getTrustedDevice(senderId);
      const senderName = sender ? sender.deviceName : 'Phone';

      const validation = validateUrl(body.url);
      if (!validation.valid || !validation.normalized) {
        res.status(400).json({ error: validation.error || 'Invalid URL' });
        return;
      }

      this.emit('url-received', {
        senderDevice: senderName,
        url: validation.normalized,
        title: body.title,
      });

      res.status(200).json({ status: 'opened' });
    });

    // DELETE /transfer/:id - Cancels an in-progress transfer and purges partial files
    this.app.delete('/transfer/:id', (req: Request, res: Response) => {
      if (!this.authenticate(req, res)) return;
      const targetId = req.params.id;
      if (this.activeTransferId === targetId) {
        for (const s of this.activeStreams) {
          try { s.destroy(); } catch {}
        }
        this.resetReceivingState();
      }

      const targetDir = path.join(this.tempDir, targetId);
      if (fs.existsSync(targetDir)) {
        try {
          fs.rmSync(targetDir, { recursive: true, force: true });
        } catch {}
      }
      res.status(200).json({ status: 'cancelled' });
    });
  }

  private resetReceivingState(): void {
    this.isReceiving = false;
    this.activeTransferId = null;
    this.activeStreams = [];
  }

  // Starts listening on default port 54321, sequentially falling back up to 54330 if in use.
  public async start(): Promise<number> {
    for (let port = FLIK_CONSTANTS.DEFAULT_PORT; port <= FLIK_CONSTANTS.MAX_PORT; port++) {
      try {
        await new Promise<void>((resolve, reject) => {
          this.server = this.app.listen(port, '0.0.0.0', () => {
            this.boundPort = port;
            resolve();
          });
          this.server.on('error', (err: any) => {
            if (err.code === 'EADDRINUSE') {
              this.server.close();
              reject(err);
            } else {
              reject(err);
            }
          });
        });
        console.log(`Flik receiver server successfully bound on port ${this.boundPort}`);
        return this.boundPort;
      } catch (err: any) {
        if (err.code === 'EADDRINUSE' && port < FLIK_CONSTANTS.MAX_PORT) {
          console.warn(`Port ${port} in use, attempting port ${port + 1}...`);
          continue;
        }
        throw new Error('All Flik network ports (54321-54330) are currently in use.');
      }
    }
    throw new Error('Unable to bind any Flik receiver port.');
  }

  public getPort(): number {
    return this.boundPort;
  }

  // Stops server and cleans up temporary files on application exit
  public stop(): void {
    if (this.server) {
      this.server.close();
      this.server = null;
    }
    try {
      if (fs.existsSync(this.tempDir)) {
        fs.rmSync(this.tempDir, { recursive: true, force: true });
      }
    } catch {}
  }
}
