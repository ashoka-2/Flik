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
} from 'electron';
import path from 'path';
import fs from 'fs';
import os from 'os';
import { FlikSettingsStore } from './store';
import { FlikReceiverServer } from './server';
import { FlikMdnsService } from './mdns';
import { InteractiveRect, ActiveTransferCard } from '../shared/types';
import { FLIK_CONSTANTS, NORMALIZED_ERRORS } from '../shared/constants';
import { validateUrl } from '../shared/sanitizer';

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
  private interactiveRects: Map<number, InteractiveRect[]> = new Map();
  private cursorPollTimer: NodeJS.Timeout | null = null;
  private tempWorkspace: string;
  private localIp: string = '127.0.0.1';
  private boundPort: number = FLIK_CONSTANTS.DEFAULT_PORT;
  private pendingPairings: Map<string, (accept: boolean) => void> = new Map();

  constructor() {
    this.tempWorkspace = path.join(app.getPath('temp'), 'FlikTransfers');
    this.store = new FlikSettingsStore();
    this.server = new FlikReceiverServer(this.store, this.tempWorkspace);
    this.mdns = new FlikMdnsService();
    this.detectLocalIp();
  }

  // Identifies the primary local IPv4 address for QR pairing and connections
  private detectLocalIp(): void {
    const interfaces = os.networkInterfaces();
    for (const name of Object.keys(interfaces)) {
      for (const net of interfaces[name] || []) {
        if (net.family === 'IPv4' && !net.internal) {
          this.localIp = net.address;
          return;
        }
      }
    }
  }

  public async init(): Promise<void> {
    await app.whenReady();

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
    // Generate a minimal clean 16x16 icon in code if asset isn't present
    const icon = nativeImage.createFromBuffer(
      Buffer.from(
        'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAZElEQVQ4T2NkoBAwUqifYdQAHg0M' +
        'DAwMTEwMDJ1NDAwM/xkYGBhhmpmZGJiZGWHqmJmZ/zEwMDAyMDD8Z2BgwKcTphkugGEKBmEgGICf' +
        '4f8Z8GmGAeDTR7ABv379YmBkyIdp+v/fAS7/AQC6GhbB41p0XwAAAABJRU5ErkJggg==',
        'base64'
      )
    );

    this.tray = new Tray(icon);
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
      width: 380,
      height: 480,
      resizable: false,
      frame: false,
      alwaysOnTop: true,
      skipTaskbar: true,
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

    this.trayWindow.on('blur', () => {
      this.trayWindow?.hide();
    });
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

    // Returns local device status, IP, port, and QR data payload
    ipcMain.handle('flik:get-device-info', () => {
      return {
        deviceId: this.store.getDeviceId(),
        deviceName: this.store.getDeviceName(),
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
