// Secure Electron Preload script exposing typed IPC methods to the Flik renderer.

import { contextBridge, ipcRenderer } from 'electron';
import { InteractiveRect } from '../shared/types';

const flikApi = {
  // Initiates Windows native file drag-out from a card into desktop or other apps
  startDrag: (filePath: string) => {
    ipcRenderer.send('flik:start-drag', filePath);
  },

  // Reports interactive card and toolbar bounding boxes for click-through cursor polling
  reportInteractiveRects: (rects: InteractiveRect[]) => {
    ipcRenderer.send('flik:update-rects', rects);
  },

  // Responds to incoming pairing approval dialog
  respondPairing: (requestId: string, accept: boolean) => {
    ipcRenderer.send('flik:pairing-response', { requestId, accept });
  },

  // Requests opening safe external URL
  openUrl: (url: string) => {
    ipcRenderer.send('flik:open-url', url);
  },

  // Opens folder in Windows Explorer
  openFolder: (folderPath: string) => {
    ipcRenderer.send('flik:open-folder', folderPath);
  },

  // Opens file in default Windows viewer
  openFile: (filePath: string) => {
    ipcRenderer.send('flik:open-file', filePath);
  },

  // Highlights and selects file in File Explorer
  showInFolder: (filePath: string) => {
    ipcRenderer.send('flik:show-in-folder', filePath);
  },

  // Copies image file to system clipboard
  copyImage: async (filePath: string): Promise<boolean> => {
    return await ipcRenderer.invoke('flik:copy-image', filePath);
  },

  // Prompts native folder picker to save stacked cards into a permanent folder
  saveFilesToFolder: async (filePaths: string[]): Promise<boolean> => {
    return await ipcRenderer.invoke('flik:save-files-to-folder', filePaths);
  },

  // Deletes transferred temp files
  deleteFiles: (filePaths: string[]) => {
    ipcRenderer.send('flik:delete-files', filePaths);
  },

  // Reads media file into base64 data URL for 100% reliable image card rendering
  readMediaDataUrl: async (filePath: string): Promise<string | null> => {
    return await ipcRenderer.invoke('flik:read-media-data-url', filePath);
  },

  // Storage destination folder management
  getStoragePath: async (): Promise<string> => {
    return await ipcRenderer.invoke('flik:get-storage-path');
  },

  setStoragePath: async (dirPath: string): Promise<boolean> => {
    return await ipcRenderer.invoke('flik:set-storage-path', dirPath);
  },

  chooseStoragePath: async (): Promise<string | null> => {
    return await ipcRenderer.invoke('flik:choose-storage-path');
  },

  // Sets human-readable device name
  setDeviceName: async (name: string) => {
    return await ipcRenderer.invoke('flik:set-device-name', name);
  },

  // Prompts file picker to send files to an Android phone
  promptSendFiles: async (peerDeviceId?: string): Promise<boolean> => {
    return await ipcRenderer.invoke('flik:prompt-send-files', peerDeviceId);
  },

  // Sends dropped files to target phone
  sendDroppedFiles: async (filePaths: string[], peerDeviceId?: string): Promise<boolean> => {
    return await ipcRenderer.invoke('flik:send-dropped-files', { filePaths, peerDeviceId });
  },

  // Fetches local system status, IPv4, bound port, and QR pairing string
  getDeviceInfo: async () => {
    return await ipcRenderer.invoke('flik:get-device-info');
  },

  // Sends a Web URL to the phone to open in browser
  sendUrlToPhone: async (url: string, peerDeviceId?: string): Promise<boolean> => {
    return await ipcRenderer.invoke('flik:send-url-to-phone', { url, peerDeviceId });
  },

  // Fetches list of discovered peers
  getPeers: async () => {
    return await ipcRenderer.invoke('flik:get-peers');
  },

  // Closes/minimizes the dashboard window to system tray
  closeDashboard: () => {
    ipcRenderer.send('flik:close-dashboard');
  },

  // Configures Start with Windows
  setStartWithWindows: async (enable: boolean) => {
    return await ipcRenderer.invoke('flik:set-start-with-windows', enable);
  },

  getStartWithWindows: async () => {
    return await ipcRenderer.invoke('flik:get-start-with-windows');
  },

  // Listeners for events from the Electron main process
  onPairingRequest: (callback: (request: any) => void) => {
    const sub = (_: any, data: any) => callback(data);
    ipcRenderer.on('flik:pairing-request', sub);
    return () => ipcRenderer.removeListener('flik:pairing-request', sub);
  },

  onTransferReceived: (callback: (card: any) => void) => {
    const sub = (_: any, data: any) => callback(data);
    ipcRenderer.on('flik:transfer-received', sub);
    return () => ipcRenderer.removeListener('flik:transfer-received', sub);
  },

  onUrlReceived: (callback: (data: any) => void) => {
    const sub = (_: any, data: any) => callback(data);
    ipcRenderer.on('flik:url-received', sub);
    return () => ipcRenderer.removeListener('flik:url-received', sub);
  },

  onToast: (callback: (message: string) => void) => {
    const sub = (_: any, msg: string) => callback(msg);
    ipcRenderer.on('flik:toast', sub);
    return () => ipcRenderer.removeListener('flik:toast', sub);
  },

  onPeersUpdated: (callback: (peers: any[]) => void) => {
    const sub = (_: any, peers: any[]) => callback(peers);
    ipcRenderer.on('flik:peers-updated', sub);
    return () => ipcRenderer.removeListener('flik:peers-updated', sub);
  },

  onClientsUpdated: (callback: (clients: any[]) => void) => {
    const sub = (_: any, clients: any[]) => callback(clients);
    ipcRenderer.on('flik:clients-updated', sub);
    return () => ipcRenderer.removeListener('flik:clients-updated', sub);
  },
};

export type FlikApi = typeof flikApi;

contextBridge.exposeInMainWorld('flik', flikApi);
