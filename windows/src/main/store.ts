// Manages persistent configuration, trusted paired devices, and security tokens for Flik Windows.

import Store from 'electron-store';
import crypto from 'crypto';
import os from 'os';
import { TrustedDevice } from '../shared/types';
import { constantTimeCompare } from '../shared/crypto';

interface FlikStoreSchema {
  deviceId: string;
  deviceName: string;
  trustedDevices: Record<string, TrustedDevice>;
  startWithWindows: boolean;
}

export class FlikSettingsStore {
  private store: Store<FlikStoreSchema>;

  constructor() {
    this.store = new Store<FlikStoreSchema>({
      name: 'flik-settings',
      defaults: {
        deviceId: crypto.randomUUID(),
        deviceName: os.hostname() || 'Windows PC',
        trustedDevices: {},
        startWithWindows: false,
      },
    });
  }

  public getDeviceId(): string {
    let id = this.store.get('deviceId');
    if (!id) {
      id = crypto.randomUUID();
      this.store.set('deviceId', id);
    }
    return id;
  }

  public getDeviceName(): string {
    return this.store.get('deviceName') || os.hostname() || 'Windows PC';
  }

  public setDeviceName(name: string): void {
    this.store.set('deviceName', name.trim());
  }

  public getTrustedDevices(): TrustedDevice[] {
    const map = this.store.get('trustedDevices') || {};
    return Object.values(map);
  }

  public getTrustedDevice(deviceId: string): TrustedDevice | undefined {
    const map = this.store.get('trustedDevices') || {};
    return map[deviceId];
  }

  public saveTrustedDevice(device: TrustedDevice): void {
    const map = this.store.get('trustedDevices') || {};
    map[device.deviceId] = { ...device, lastSeen: Date.now() };
    this.store.set('trustedDevices', map);
  }

  public removeTrustedDevice(deviceId: string): void {
    const map = this.store.get('trustedDevices') || {};
    delete map[deviceId];
    this.store.set('trustedDevices', map);
  }

  public verifyToken(deviceId: string, token: string): boolean {
    const device = this.getTrustedDevice(deviceId);
    if (!device || !device.token) {
      return false;
    }
    return constantTimeCompare(device.token, token);
  }

  public getStartWithWindows(): boolean {
    return this.store.get('startWithWindows', false);
  }

  public setStartWithWindows(val: boolean): void {
    this.store.set('startWithWindows', val);
  }
}
