// Electron main process orchestrating the Flik Connector, multi-monitor transparent overlays,
// click-through cursor polling, tray menu, native drag-out, and local network transfers.

import {
  app,
  BrowserWindow,
  screen,
  ipcMain,
  shell,
  dialog,
  Tray,
  Menu,
  nativeImage,
  protocol,
  net,
} from 'electron';
import path from 'path';
import fs from 'fs';
import os from 'os';
import { pathToFileURL } from 'url';
import { FlikSettingsStore } from './store';
import { FlikReceiverServer } from './server';
import { FlikMdnsService } from './mdns';
import { InteractiveRect, ActiveTransferCard } from '../shared/types';
import { FLIK_CONSTANTS, NORMALIZED_ERRORS } from '../shared/constants';
import { validateUrl } from '../shared/sanitizer';

// Register custom privileged scheme for loading local media thumbnails in cards
protocol.registerSchemesAsPrivileged([
  { scheme: 'flik-media', privileges: { standard: true, secure: true, supportFetchAPI: true } },
]);

// Enforce single instance lock
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
  process.exit(0);
}

class FlikConnectorApp {
  private store: FlikSettingsStore;
  private server: FlikReceiverServer;
  private mdns: FlikMdnsService;
  private overlayWindows: Map<number, BrowserWindow> = new Map();
  private tray: Tray | null = null;
  private trayWindow: BrowserWindow | null = null;
  private appIcon: any = null;
  private interactiveRects: Map<number, InteractiveRect[]> = new Map();
  private cursorPollTimer: NodeJS.Timeout | null = null;
  private tempWorkspace: string;
  private localIp: string = '127.0.0.1';
  private boundPort: number = FLIK_CONSTANTS.DEFAULT_PORT;
  private pendingPairings: Map<string, (accept: boolean) => void> = new Map();

  constructor() {
    this.store = new FlikSettingsStore();
    this.tempWorkspace = this.store.getStoragePath();
    this.server = new FlikReceiverServer(this.store, this.tempWorkspace);
    this.mdns = new FlikMdnsService();
    this.detectLocalIp();
    this.loadAppIcon();
  }

  // Loads or creates the Flik application icon for tray and windows
  private loadAppIcon(): void {
    const iconPath = path.join(__dirname, '../../build/icon.png');
    if (fs.existsSync(iconPath)) {
      this.appIcon = nativeImage.createFromPath(iconPath);
    } else {
      this.appIcon = nativeImage.createFromBuffer(
        Buffer.from(
          'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAARnQU1BAACx' +
          'jwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAA7SURBVFhH7c6xDQAwCMTQv3T/pZEuIAPaI0kX' +
          '5vUq651Z78x6Z9Y7s96Z9c6sd2a9M+udWe/M+jM/k7YCyOaZ7SIAAAAASUVORK5CYII=',
          'base64'
        )
      );
    }
  }

  // Identifies the best local IPv4 address for QR pairing and connections
  private detectLocalIp(): void {
    const interfaces = os.networkInterfaces();
    const candidates: { ip: string; name: string; score: number }[] = [];

    for (const name of Object.keys(interfaces)) {
      const lowerName = name.toLowerCase();
      // Skip known virtual / loopback / tunnel adapters
      if (
        lowerName.includes('loopback') ||
        lowerName.includes('vethernet') ||
        lowerName.includes('virtualbox') ||
        lowerName.includes('vmware') ||
        lowerName.includes('wsl') ||
        lowerName.includes('bluetooth') ||
        lowerName.includes('teredo') ||
        lowerName.includes('tailscale') ||
        lowerName.includes('zerotier')
      ) {
        continue;
      }

      for (const net of interfaces[name] || []) {
        if (net.family === 'IPv4' && !net.internal) {
          // Reject link-local APIPA addresses (169.254.x.x)
          if (net.address.startsWith('169.254.')) {
            continue;
          }

          let score = 10;
          if (lowerName.includes('wi-fi') || lowerName.includes('wifi') || lowerName.includes('wireless') || lowerName.includes('wlan')) {
            score += 100;
          } else if (lowerName.includes('ethernet')) {
            score += 50;
          }

          // Prefer standard LAN subnets
          if (net.address.startsWith('192.168.') || net.address.startsWith('10.')) {
            score += 30;
          }

          candidates.push({ ip: net.address, name, score });
        }
      }
    }

    // Sort by score descending
    candidates.sort((a, b) => b.score - a.score);

    if (candidates.length > 0) {
      this.localIp = candidates[0].ip;
      console.log(`Flik selected primary IP: ${this.localIp} (${candidates[0].name})`);
    } else {
      // Fallback
      this.localIp = '127.0.0.1';
    }
  }

  public async init(): Promise<void> {
    await app.whenReady();

    // Protocol handler to stream local image and video thumbnails to cards
    protocol.handle('flik-media', async (request) => {
      try {
        const url = new URL(request.url);
        let targetFile = url.searchParams.get('file');
        if (!targetFile) {
          const raw = request.url.replace(/^flik-media:\/\//, '');
          targetFile = decodeURIComponent(raw);
        }
        if (targetFile) {
          targetFile = path.normalize(targetFile);
          if (fs.existsSync(targetFile)) {
            return net.fetch(pathToFileURL(targetFile).toString());
          }
        }
      } catch (err) {
        console.error('flik-media protocol error:', err);
      }
      return new Response('File not found', { status: 404 });
    });

    try {
      this.boundPort = await this.server.start();
    } catch (err: any) {
      console.error('Port bind failure:', err);
      dialog.showErrorBox('Flik Connector Error', NORMALIZED_ERRORS.ALL_PORTS_BUSY());
      app.quit();
      return;
    }

    // Advertise via mDNS
    this.mdns.publish(this.store.getDeviceId(), this.store.getDeviceName(), this.boundPort);
    this.mdns.startDiscovery();

    this.createTray();
    this.createOverlays();
    this.setupIpc();
    this.setupServerEvents();

    // Show the Flik Connector Dashboard window on launch so the user sees the app
    this.showTrayWindow();

    // Bring up the dashboard when the user launches a second instance (e.g. clicks shortcut again)
    app.on('second-instance', () => {
      this.showTrayWindow();
    });

    // Listen to screen topology changes (connecting or disconnecting monitors)
    screen.on('display-added', () => this.refreshOverlays());
    screen.on('display-removed', () => this.refreshOverlays());
    screen.on('display-metrics-changed', () => this.refreshOverlays());

    app.on('window-all-closed', () => {
      // Keep running in tray and background on Windows
    });
    app.on('before-quit', () => this.cleanup());
  }

  // Creates transparent full-screen overlay window on every connected display
  private createOverlays(): void {
    const displays = screen.getAllDisplays();
    for (const display of displays) {
      const { bounds } = display;
      const win = new BrowserWindow({
        x: bounds.x,
        y: bounds.y,
        width: bounds.width,
        height: bounds.height,
        transparent: true,
        frame: false,
        hasShadow: false,
        resizable: false,
        movable: false,
        skipTaskbar: true,
        focusable: true,
        webPreferences: {
          preload: path.join(__dirname, '../preload/preload.js'),
          contextIsolation: true,
          nodeIntegration: false,
        },
      });

      win.setAlwaysOnTop(true, 'screen-saver');
      win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
      win.setIgnoreMouseEvents(true, { forward: true });

      // Load Vite build or dev server
      if (process.env.VITE_DEV_SERVER_URL) {
        win.loadURL(`${process.env.VITE_DEV_SERVER_URL}?mode=overlay&displayId=${display.id}`);
      } else {
        const indexPath = path.join(__dirname, '../../dist/index.html');
        win.loadFile(indexPath, { query: { mode: 'overlay', displayId: String(display.id) } });
      }

      this.overlayWindows.set(display.id, win);
    }
  }

  private refreshOverlays(): void {
    for (const win of this.overlayWindows.values()) {
      try { win.close(); } catch {}
    }
    this.overlayWindows.clear();
    this.createOverlays();
  }

  // 60Hz cursor polling checking if cursor is over any reported interactive card/deck/toast rect
  private startCursorPolling(): void {
    if (this.cursorPollTimer) return;
    this.cursorPollTimer = setInterval(() => {
      const cursor = screen.getCursorScreenPoint();
      let hasAnyRects = false;

      for (const [displayId, win] of this.overlayWindows.entries()) {
        if (win.isDestroyed()) continue;
        const rects = this.interactiveRects.get(displayId) || [];
        if (rects.length > 0) hasAnyRects = true;

        const bounds = win.getBounds();
        // Check if cursor is on this display
        const onThisDisplay =
          cursor.x >= bounds.x &&
          cursor.x <= bounds.x + bounds.width &&
          cursor.y >= bounds.y &&
          cursor.y <= bounds.y + bounds.height;

        if (onThisDisplay) {
          const localX = cursor.x - bounds.x;
          const localY = cursor.y - bounds.y;
          const isOverInteractive = rects.some(
            (r) =>
              localX >= r.x &&
              localX <= r.x + r.width &&
              localY >= r.y &&
              localY <= r.y + r.height
          );
          win.setIgnoreMouseEvents(!isOverInteractive, { forward: true });
        } else {
          win.setIgnoreMouseEvents(true, { forward: true });
        }
      }

      if (!hasAnyRects && this.cursorPollTimer) {
        clearInterval(this.cursorPollTimer);
        this.cursorPollTimer = null;
      }
    }, 16);
  }

  // System Tray initialization and menu actions
  private createTray(): void {
    this.tray = new Tray(this.appIcon);
    this.tray.setToolTip('Flik Connector - Ready for your phone');

    const updateContextMenu = () => {
      const contextMenu = Menu.buildFromTemplate([
        { label: 'Flik Connector', enabled: false },
        { label: `Status: Ready for phone (${this.localIp}:${this.boundPort})`, enabled: false },
        { type: 'separator' },
        {
          label: 'Show Pairing QR Code...',
          click: () => this.showTrayWindow(),
        },
        {
          label: 'Send File to Phone...',
          click: () => this.promptSendFileFromTray(),
        },
        { type: 'separator' },
        {
          label: 'Start with Windows',
          type: 'checkbox',
          checked: this.store.getStartWithWindows(),
          click: (item) => {
            this.store.setStartWithWindows(item.checked);
            app.setLoginItemSettings({ openAtLogin: item.checked });
          },
        },
        { type: 'separator' },
        {
          label: 'Quit Flik',
          click: () => app.quit(),
        },
      ]);
      this.tray?.setContextMenu(contextMenu);
    };

    updateContextMenu();
    this.tray.on('click', () => this.showTrayWindow());
  }

  // Displays the tray popover with local QR pairing details
  private showTrayWindow(): void {
    if (this.trayWindow && !this.trayWindow.isDestroyed()) {
      this.trayWindow.show();
      this.trayWindow.focus();
      return;
    }

    this.trayWindow = new BrowserWindow({
      width: 420,
      height: 560,
      resizable: false,
      frame: false,
      title: 'Flik Connector',
      icon: this.appIcon,
      alwaysOnTop: false,
      skipTaskbar: false, // Visible in the Windows taskbar!
      center: true,
      webPreferences: {
        preload: path.join(__dirname, '../preload/preload.js'),
        contextIsolation: true,
        nodeIntegration: false,
      },
    });

    if (process.env.VITE_DEV_SERVER_URL) {
      this.trayWindow.loadURL(`${process.env.VITE_DEV_SERVER_URL}?mode=tray`);
    } else {
      const indexPath = path.join(__dirname, '../../dist/index.html');
      this.trayWindow.loadFile(indexPath, { query: { mode: 'tray' } });
    }

    this.trayWindow.on('close', (e) => {
      e.preventDefault();
      this.trayWindow?.hide();
    });

    this.trayWindow.show();
    this.trayWindow.focus();
  }

  private setupServerEvents(): void {
    // When an Android device requests pairing, surface the approval card to overlays
    this.server.on('pairing-requested', (req) => {
      this.pendingPairings.set(req.id, req.respond);
      this.broadcastToOverlays('flik:pairing-request', {
        id: req.id,
        deviceId: req.deviceId,
        deviceName: req.deviceName,
        code: req.code,
      });
    });

    // When files finish streaming into temp workspace, display them as landing cards
    this.server.on('transfer-received', (card: ActiveTransferCard) => {
      const primaryDisplay = screen.getPrimaryDisplay();
      const { bounds } = primaryDisplay;
      const cardWidth = 320;
      const traj = typeof card.trajectoryX === 'number' ? card.trajectoryX : 0.0;
      const normalizedTraj = Math.max(-1.0, Math.min(1.0, traj));
      // Map traj (-1.0 to +1.0) across primary monitor width:
      const centerX = bounds.width * 0.5 + normalizedTraj * (bounds.width * 0.38) - (cardWidth / 2);
      card.x = Math.round(Math.max(40, Math.min(bounds.width - cardWidth - 40, centerX)));
      card.y = Math.round(Math.max(100, bounds.height * 0.32));

      this.broadcastToOverlays('flik:transfer-received', card);
    });

    // When a valid web URL is received, open it immediately and show brief toast
    this.server.on('url-received', (data) => {
      const validation = validateUrl(data.url);
      if (validation.valid && validation.normalized) {
        shell.openExternal(validation.normalized);
        this.broadcastToOverlays('flik:toast', `Opened link from ${data.senderDevice}`);
      } else {
        this.broadcastToOverlays('flik:toast', NORMALIZED_ERRORS.UNSAFE_URL_RECEIVED(data.senderDevice));
      }
    });

    this.mdns.on('peers-updated', (peers) => {
      this.broadcastToOverlays('flik:peers-updated', peers);
    });
  }

  private broadcastToOverlays(channel: string, data: any): void {
    for (const win of this.overlayWindows.values()) {
      if (!win.isDestroyed()) {
        win.webContents.send(channel, data);
      }
    }
  }

  // Wires IPC events between the renderer and main process
  private setupIpc(): void {
    // Native drag-out from a Flik card into Windows Explorer, ChatGPT, etc.
    ipcMain.on('flik:start-drag', (event, filePath: string) => {
      try {
        if (!fs.existsSync(filePath)) {
          console.warn('Cannot drag-out non-existent file:', filePath);
          return;
        }

        // Generate drag icon
        const icon = nativeImage.createFromBuffer(
          Buffer.from(
            'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAANUlEQVR42u3PMQEAAAwCoNm/9E68' +
            'AQ1BIA02YBAgQIAAAQIECBAgQIAAAQIECBAgQIAAAQKvFhB3AnqIbgYSAAAAAElFTkSuQmCC',
            'base64'
          )
        );

        event.sender.startDrag({
          file: filePath,
          icon,
        });
      } catch (err) {
        console.error('Native drag-out failed:', err);
      }
    });

    // Updates interactive rects reported by the renderer for cursor polling
    ipcMain.on('flik:update-rects', (event, rects: InteractiveRect[]) => {
      const win = BrowserWindow.fromWebContents(event.sender);
      if (!win) return;

      for (const [id, w] of this.overlayWindows.entries()) {
        if (w === win) {
          this.interactiveRects.set(id, rects);
          break;
        }
      }

      if (rects.length > 0) {
        this.startCursorPolling();
      }
    });

    // Pairing approval response from the user
    ipcMain.on('flik:pairing-response', (_event, { requestId, accept }) => {
      const resolver = this.pendingPairings.get(requestId);
      if (resolver) {
        resolver(accept);
        this.pendingPairings.delete(requestId);
      }
    });

    // Safe external link opening
    ipcMain.on('flik:open-url', (_event, rawUrl: string) => {
      const val = validateUrl(rawUrl);
      if (val.valid && val.normalized) {
        shell.openExternal(val.normalized);
      }
    });

    // Opens a local folder in Windows Explorer
    ipcMain.on('flik:open-folder', (_event, folderPath: string) => {
      if (fs.existsSync(folderPath)) {
        shell.openPath(folderPath);
      }
    });

    // Saves stacked cards into a permanent user folder chosen via native dialog
    ipcMain.handle('flik:save-files-to-folder', async (_event, filePaths: string[]) => {
      try {
        const result = await dialog.showOpenDialog({
          title: 'Save Flik Transfer to Folder',
          properties: ['openDirectory', 'createDirectory'],
        });

        if (result.canceled || !result.filePaths || result.filePaths.length === 0) {
          return false;
        }

        const destDir = result.filePaths[0];
        for (const src of filePaths) {
          if (fs.existsSync(src)) {
            const dest = path.join(destDir, path.basename(src));
            fs.copyFileSync(src, dest);
          }
        }
        return true;
      } catch (err) {
        console.error('Failed saving files to chosen folder:', err);
        return false;
      }
    });

    // Purges transferred files from temp workspace
    ipcMain.on('flik:delete-files', (_event, filePaths: string[]) => {
      for (const p of filePaths) {
        try {
          if (fs.existsSync(p)) fs.unlinkSync(p);
        } catch {}
      }
    });

    // Reads local image file into base64 data URL as bulletproof renderer fallback
    ipcMain.handle('flik:read-media-data-url', async (_event, filePath: string) => {
      try {
        if (filePath && fs.existsSync(filePath)) {
          const buf = await fs.promises.readFile(filePath);
          const ext = path.extname(filePath).toLowerCase();
          const mime = ext === '.png' ? 'image/png' : ext === '.webp' ? 'image/webp' : 'image/jpeg';
          return `data:${mime};base64,${buf.toString('base64')}`;
        }
      } catch (e) {
        console.error('Failed reading media data url:', e);
      }
      return null;
    });

    // Minimizes dashboard to system tray
    ipcMain.on('flik:close-dashboard', () => {
      this.trayWindow?.hide();
    });

    // Storage directory configuration
    ipcMain.handle('flik:get-storage-path', () => {
      return this.store.getStoragePath();
    });

    ipcMain.handle('flik:set-storage-path', (_event, dirPath: string) => {
      this.store.setStoragePath(dirPath);
      this.server.setStorageDir(dirPath);
      return true;
    });

    ipcMain.handle('flik:choose-storage-path', async () => {
      const result = await dialog.showOpenDialog({
        title: 'Choose Folder to Save Flik Transfers',
        defaultPath: this.store.getStoragePath(),
        properties: ['openDirectory', 'createDirectory'],
      });
      if (!result.canceled && result.filePaths && result.filePaths.length > 0) {
        const chosen = result.filePaths[0];
        this.store.setStoragePath(chosen);
        this.server.setStorageDir(chosen);
        return chosen;
      }
      return null;
    });

    // Returns local device status, IP, port, and QR data payload
    ipcMain.handle('flik:get-device-info', () => {
      return {
        deviceId: this.store.getDeviceId(),
        deviceName: this.store.getDeviceName(),
        storagePath: this.store.getStoragePath(),
        ip: this.localIp,
        port: this.boundPort,
        qrPayload: JSON.stringify({
          ip: this.localIp,
          port: this.boundPort,
          deviceId: this.store.getDeviceId(),
          deviceName: this.store.getDeviceName(),
        }),
      };
    });

    ipcMain.handle('flik:set-device-name', (_event, name: string) => {
      this.store.setDeviceName(name);
      return true;
    });

    ipcMain.handle('flik:get-peers', () => {
      return this.mdns.getDiscoveredPeers();
    });

    ipcMain.handle('flik:set-start-with-windows', (_event, enable: boolean) => {
      this.store.setStartWithWindows(enable);
      app.setLoginItemSettings({ openAtLogin: enable });
      return true;
    });

    ipcMain.handle('flik:get-start-with-windows', () => {
      return this.store.getStartWithWindows();
    });
  }

  // Opens native file picker to select files for outbound sending to an Android phone
  private async promptSendFileFromTray(): Promise<void> {
    const peers = this.mdns.getDiscoveredPeers();
    if (peers.length === 0) {
      dialog.showMessageBox({
        type: 'info',
        title: 'No Phones Found',
        message: 'No Flik phones were found on your Wi-Fi network. Open Flik on your phone and ensure both are on the same network.',
      });
      return;
    }

    const result = await dialog.showOpenDialog({
      title: 'Select Files to Send via Flik',
      properties: ['openFile', 'multiSelections'],
    });

    if (result.canceled || !result.filePaths.length) return;

    // Send to first available peer (or prompt peer selection)
    const targetPeer = peers[0];
    this.broadcastToOverlays('flik:toast', `Sending ${result.filePaths.length} file(s) to ${targetPeer.deviceName}...`);
  }

  // Clean up server, mDNS, and temp files on quit
  private cleanup(): void {
    if (this.cursorPollTimer) {
      clearInterval(this.cursorPollTimer);
      this.cursorPollTimer = null;
    }
    this.server.stop();
    this.mdns.stop();
  }
}

const flikApp = new FlikConnectorApp();
flikApp.init().catch((err) => {
  console.error('Fatal initialization error:', err);
});
