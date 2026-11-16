// Defines shared TypeScript types for the Flik Windows connector and protocol.

export type PlatformType = 'android' | 'windows';

export type FileKind = 'file' | 'image' | 'video' | 'audio' | 'url';

export interface TransferItemMeta {
  name: string;
  size: number;
  mime: string;
  kind: FileKind;
}

export interface TransferMeta {
  transferId: string;
  items: TransferItemMeta[];
  trajectoryX?: number;
}

export interface PairRequestPayload {
  deviceId: string;
  deviceName: string;
  platform: PlatformType;
  nonce: string;
}

export interface PairResponsePayload {
  status: 'accepted' | 'declined';
  token?: string;
}

export interface PingResponsePayload {
  deviceId: string;
  deviceName: string;
  platform: PlatformType;
  ver: number;
  freeBytes: number;
  busy: boolean;
}

export interface UrlTransferPayload {
  transferId: string;
  url: string;
  title?: string;
}

export interface TrustedDevice {
  deviceId: string;
  deviceName: string;
  platform: PlatformType;
  token: string;
  lastSeen?: number;
}

export interface DiscoveredPeer {
  deviceId: string;
  deviceName: string;
  platform: PlatformType;
  ip: string;
  port: number;
  paired: boolean;
}

export interface PendingPairRequest {
  id: string;
  deviceId: string;
  deviceName: string;
  platform: PlatformType;
  nonce: string;
  code: string;
  resolve: (accepted: boolean) => void;
  expiresAt: number;
}

export interface ActiveTransferCard {
  id: string;
  senderName: string;
  senderDeviceId: string;
  items: {
    name: string;
    size: number;
    mime: string;
    kind: FileKind;
    localPath: string;
  }[];
  url?: string;
  title?: string;
  x: number;
  y: number;
  trajectoryX?: number;
  groupId?: string;
  createdAt: number;
}

export interface InteractiveRect {
  id: string;
  x: number;
  y: number;
  width: number;
  height: number;
}
