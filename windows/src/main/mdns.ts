// Advertises and discovers Flik peers on the local network using mDNS (bonjour-service).

import { Bonjour, Service } from 'bonjour-service';
import { EventEmitter } from 'events';
import { DiscoveredPeer } from '../shared/types';
import { FLIK_CONSTANTS } from '../shared/constants';

export class FlikMdnsService extends EventEmitter {
  private bonjour: Bonjour | null = null;
  private publishedService: Service | null = null;
  private peers: Map<string, DiscoveredPeer> = new Map();
  private myDeviceId: string = '';

  constructor(myDeviceId?: string) {
    super();
    if (myDeviceId) this.myDeviceId = myDeviceId;
  }

  public setMyDeviceId(id: string): void {
    this.myDeviceId = id;
  }

  // Publishes this device on the local network so Android phones can discover it.
  public publish(deviceId: string, deviceName: string, port: number): void {
    try {
      this.bonjour = new Bonjour();
      this.publishedService = this.bonjour.publish({
        name: `Flik-${deviceName.replace(/[^a-zA-Z0-9_-]/g, '')}-${deviceId.slice(0, 4)}`,
        type: 'flik',
        port,
        txt: {
          deviceId,
          deviceName,
          platform: 'windows',
          ver: String(FLIK_CONSTANTS.PROTOCOL_VERSION),
        },
      });

      this.publishedService.on('error', (err) => {
        console.error('mDNS publish error:', err);
      });

      console.log(`mDNS advertised _flik._tcp on port ${port} as "${deviceName}"`);
    } catch (err) {
      console.error('Failed to initialize mDNS publish:', err);
    }
  }

  // Starts browsing for nearby Flik devices on the local network.
  public startDiscovery(): void {
    if (!this.bonjour) {
      this.bonjour = new Bonjour();
    }

    try {
      const browser = this.bonjour.find({ type: 'flik' });

      browser.on('up', (service: Service) => {
        const txt = service.txt || {};
        const deviceId = txt.deviceId;
        if (!deviceId) return;
        if (this.myDeviceId && deviceId === this.myDeviceId) return; // Never discover own device as peer!

        // Extract IPv4 address
        const addresses = service.addresses || [];
        const ipv4 = addresses.find((addr) => /^\d+\.\d+\.\d+\.\d+$/.test(addr)) || (service.host || '127.0.0.1');

        const peer: DiscoveredPeer = {
          deviceId,
          deviceName: txt.deviceName || service.name || 'Flik Device',
          platform: (txt.platform as any) || 'android',
          ip: ipv4,
          port: service.port,
          paired: false,
        };

        this.peers.set(deviceId, peer);
        this.emit('peers-updated', Array.from(this.peers.values()));
      });

      browser.on('down', (service: Service) => {
        const txt = service.txt || {};
        const deviceId = txt.deviceId;
        if (deviceId && this.peers.has(deviceId)) {
          this.peers.delete(deviceId);
          this.emit('peers-updated', Array.from(this.peers.values()));
        }
      });
    } catch (err) {
      console.error('Failed to start mDNS discovery:', err);
    }
  }

  public getDiscoveredPeers(): DiscoveredPeer[] {
    return Array.from(this.peers.values());
  }

  // Stops mDNS advertising and unpublishes services on shutdown.
  public stop(): void {
    try {
      if (this.publishedService) {
        this.publishedService.stop();
        this.publishedService = null;
      }
      if (this.bonjour) {
        this.bonjour.destroy();
        this.bonjour = null;
      }
    } catch (err) {
      console.error('Error stopping mDNS:', err);
    }
  }
}
