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

  // Prompts native folder picker to save stacked cards into a permanent folder
  saveFilesToFolder: async (filePaths: string[]): Promise<boolean> => {
    return await ipcRenderer.invoke('flik:save-files-to-folder', filePaths);
  },

  // Deletes transferred temp files
  deleteFiles: (filePaths: string[]) => {
    ipcRenderer.send('flik:delete-files', filePaths);
  },

  // Prompts file picker to send files to an Android phone
  promptSendFiles: async (peerDeviceId: string): Promise<boolean> => {
    return await ipcRenderer.invoke('flik:prompt-send-files', peerDeviceId);
  },

  // Fetches local system status, IPv4, bound port, and QR pairing string
  getDeviceInfo: async () => {
    return await ipcRenderer.invoke('flik:get-device-info');
  },

  // Fetches list of discovered peers
  getPeers: async () => {
    return await ipcRenderer.invoke('flik:get-peers');
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
};

export type FlikApi = typeof flikApi;

contextBridge.exposeInMainWorld('flik', flikApi);
