import React, { useEffect, useState, useRef } from 'react';
import QRCode from 'qrcode';

interface DeviceInfo {
  deviceId: string;
  deviceName: string;
  storagePath?: string;
  ip: string;
  port: number;
  qrPayload: string;
}

interface PeerDevice {
  deviceId: string;
  deviceName: string;
  ip: string;
  port: number;
  platform?: string;
  paired?: boolean;
}

export const TrayWindow: React.FC = () => {
  const [info, setInfo] = useState<DeviceInfo | null>(null);
  const [storagePath, setStoragePath] = useState<string>('');
  const [startWithWin, setStartWithWin] = useState<boolean>(false);
  const [peers, setPeers] = useState<PeerDevice[]>([]);
  const [selectedPeerId, setSelectedPeerId] = useState<string>('');
  const [editingName, setEditingName] = useState<boolean>(false);
  const [deviceName, setDeviceName] = useState<string>('');
  const [isDragOver, setIsDragOver] = useState<boolean>(false);
  const [urlToSend, setUrlToSend] = useState<string>('');
  const [showQr, setShowQr] = useState<boolean>(true);
  const canvasRef = useRef<HTMLCanvasElement>(null);

  const loadData = async () => {
    if (window.flik) {
      const devInfo = await window.flik.getDeviceInfo();
      setInfo(devInfo);
      if (devInfo) {
        setDeviceName(devInfo.deviceName);
        if (devInfo.storagePath) {
          setStoragePath(devInfo.storagePath);
        }
      }
      const sPath = await window.flik.getStoragePath?.();
      if (sPath) {
        setStoragePath(sPath);
      }
      const winStart = await window.flik.getStartWithWindows();
      setStartWithWin(winStart);
      const discovered = await window.flik.getPeers();
      setPeers(discovered || []);
      if (discovered && discovered.length > 0 && !selectedPeerId) {
        setSelectedPeerId(discovered[0].deviceId);
      }
    }
  };

  useEffect(() => {
    loadData();

    const unsubPeers = window.flik?.onPeersUpdated((updated: PeerDevice[]) => {
      setPeers(updated || []);
      if (updated && updated.length > 0) {
        setSelectedPeerId((prev) => (prev ? prev : updated[0].deviceId));
      }
    });

    const unsubClients = (window.flik as any)?.onClientsUpdated?.((clients: PeerDevice[]) => {
      setPeers((prev) => {
        const map = new Map<string, PeerDevice>();
        for (const p of prev) map.set(p.deviceId, p);
        for (const c of clients) map.set(c.deviceId, c);
        const list = Array.from(map.values());
        if (list.length > 0 && !selectedPeerId) setSelectedPeerId(list[0].deviceId);
        return list;
      });
    });

    return () => {
      if (unsubPeers) unsubPeers();
      if (unsubClients) unsubClients();
    };
  }, []);

  const saveDeviceName = async () => {
    if (!deviceName.trim()) return;
    await window.flik?.setDeviceName(deviceName.trim());
    setEditingName(false);
    const updated = await window.flik?.getDeviceInfo();
    if (updated) setInfo(updated);
  };

  const handleChooseFolder = async () => {
    if (window.flik?.chooseStoragePath) {
      const chosen = await window.flik.chooseStoragePath();
      if (chosen) {
        setStoragePath(chosen);
      }
    }
  };

  useEffect(() => {
    if (info && canvasRef.current) {
      QRCode.toCanvas(canvasRef.current, info.qrPayload, {
        width: 150,
        margin: 1,
        color: {
          dark: '#000000',
          light: '#ffffff',
        },
      });
    }
  }, [info, showQr]);

  const toggleStartWithWindows = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = e.target.checked;
    setStartWithWin(val);
    await window.flik?.setStartWithWindows(val);
  };

  const activeTargetPeer = peers.find((p) => p.deviceId === selectedPeerId) || peers[0];

  const handleSendFileToPhone = async () => {
    await window.flik?.promptSendFiles(activeTargetPeer?.deviceId);
  };

  const handleSendUrl = async () => {
    if (!urlToSend.trim()) return;
    let url = urlToSend.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = `https://${url}`;
    }
    const success = await (window.flik as any)?.sendUrlToPhone?.(url, activeTargetPeer?.deviceId);
    if (success) {
      setUrlToSend('');
    }
  };

  return (
    <div className="tray-shell">
      {/* Top Header */}
      <div className="tray-header">
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <div
            style={{
              width: 32,
              height: 32,
              borderRadius: '50%',
              backgroundColor: 'var(--accent)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontWeight: 700,
              fontSize: 16,
              color: '#ffffff',
            }}
          >
            F
          </div>
          <div>
            {editingName ? (
              <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
                <input
                  type="text"
                  value={deviceName}
                  onChange={(e) => setDeviceName(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && saveDeviceName()}
                  style={{
                    fontSize: 14,
                    padding: '2px 8px',
                    borderRadius: 6,
                    border: '1px solid var(--accent)',
                    background: 'var(--surface)',
                    color: 'var(--text)',
                    width: 140,
                  }}
                  autoFocus
                />
                <button
                  className="btn-pill primary"
                  style={{ padding: '2px 8px', fontSize: 11 }}
                  onClick={saveDeviceName}
                >
                  Save
                </button>
              </div>
            ) : (
              <div
                style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}
                onClick={() => setEditingName(true)}
                title="Click to rename this PC"
              >
                <h2 className="tray-title" style={{ fontSize: 15, lineHeight: 1.2 }}>
                  {deviceName || 'Flik Connector'}
                </h2>
                <span style={{ fontSize: 11, color: 'var(--muted)', textDecoration: 'underline' }}>
                  edit
                </span>
              </div>
            )}
            <div className="status-badge" style={{ marginTop: 2, padding: '2px 8px', fontSize: 11 }}>
              <span className="status-dot"></span>
              {peers.length > 0 ? `${peers.length} Phone Connected` : 'Ready for phone'}
            </div>
          </div>
        </div>

        <button
          className="btn-pill"
          style={{ width: 30, height: 30, padding: 0, fontSize: 13 }}
          title="Minimize to Tray"
          onClick={() => window.flik?.closeDashboard?.()}
        >
          ✕
        </button>
      </div>

      {/* Connected Phones Banner */}
      {peers.length > 0 && (
        <div
          style={{
            padding: '10px 12px',
            borderRadius: 12,
            background: 'rgba(34, 197, 94, 0.12)',
            border: '1px solid rgba(34, 197, 94, 0.35)',
            display: 'flex',
            flexDirection: 'column',
            gap: 6,
          }}
        >
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span style={{ fontSize: 11, color: '#4ade80', fontWeight: 700, textTransform: 'uppercase', letterSpacing: 0.5 }}>
              Connected Phone
            </span>
            <span style={{ fontSize: 11, color: 'var(--muted)' }}>
              {activeTargetPeer?.ip}:{activeTargetPeer?.port || 54321}
            </span>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ fontSize: 16 }}>📱</span>
            <span style={{ fontSize: 13, fontWeight: 600, color: '#ffffff' }}>
              {activeTargetPeer?.deviceName || 'Android Phone'}
            </span>
            <span style={{ fontSize: 10, background: '#22c55e', color: '#000', padding: '1px 6px', borderRadius: 10, fontWeight: 700 }}>
              ONLINE
            </span>
          </div>
        </div>
      )}

      {/* QR Code Section (Collapsible if phone is connected) */}
      <div
        style={{
          borderRadius: 12,
          background: 'var(--surface)',
          border: '1px solid var(--line)',
          padding: 12,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          gap: 8,
        }}
      >
        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            width: '100%',
            cursor: 'pointer',
          }}
          onClick={() => setShowQr(!showQr)}
        >
          <span style={{ fontSize: 12, fontWeight: 600, color: 'var(--text)' }}>
            Pair with Phone (QR & IP)
          </span>
          <span style={{ fontSize: 11, color: 'var(--accentSoft)' }}>
            {showQr ? '▲ Hide' : '▼ Show QR'}
          </span>
        </div>

        {showQr && (
          <>
            <canvas ref={canvasRef} className="qr-canvas" style={{ width: 140, height: 140 }}></canvas>
            <p className="qr-instruction" style={{ fontSize: 11, margin: 0, textAlign: 'center' }}>
              Scan with Flik on your Android phone to pair instantly on local Wi-Fi.
            </p>
            <div
              style={{
                width: '100%',
                padding: '6px 10px',
                borderRadius: 8,
                background: 'var(--raised)',
                border: '1px solid var(--line)',
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                gap: 2,
              }}
            >
              <span style={{ fontSize: 10, color: 'var(--muted)', textTransform: 'uppercase', letterSpacing: 0.5 }}>
                Local IP
              </span>
              <span style={{ fontSize: 13, fontWeight: 700, color: 'var(--accent)', letterSpacing: 0.5 }}>
                {info ? `${info.ip}:${info.port}` : 'Detecting network...'}
              </span>
            </div>
          </>
        )}
      </div>

      {/* Storage Destination Folder Configuration */}
      <div
        style={{
          padding: '10px 12px',
          borderRadius: 12,
          background: 'var(--raised)',
          border: '1px solid var(--line)',
          display: 'flex',
          flexDirection: 'column',
          gap: 6,
        }}
      >
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span style={{ fontSize: 11, color: 'var(--muted)', textTransform: 'uppercase', fontWeight: 600, letterSpacing: 0.5 }}>
            Save Folder
          </span>
          <button
            className="btn-pill"
            style={{ height: 22, padding: '0 8px', fontSize: 11 }}
            onClick={handleChooseFolder}
          >
            Change...
          </button>
        </div>
        <div
          style={{
            fontSize: 12,
            color: 'var(--text)',
            whiteSpace: 'nowrap',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            cursor: 'pointer',
            textDecoration: 'underline dotted',
          }}
          title={storagePath ? `${storagePath} (Click to open)` : 'Click to select folder'}
          onClick={() => {
            if (storagePath) window.flik?.openFolder(storagePath);
          }}
        >
          📁 {storagePath || 'Loading path...'}
        </div>
      </div>

      {/* Desktop Dropzone for Drag-and-Drop and File Sending to Phone */}
      <div
        style={{
          padding: '16px 12px',
          borderRadius: 12,
          border: isDragOver ? '2px dashed var(--accent)' : '1px dashed var(--line)',
          background: isDragOver ? 'rgba(53, 102, 239, 0.15)' : 'var(--raised)',
          cursor: 'pointer',
          textAlign: 'center',
          transition: 'all 150ms ease',
        }}
        onDragOver={(e) => {
          e.preventDefault();
          setIsDragOver(true);
        }}
        onDragLeave={() => setIsDragOver(false)}
        onDrop={(e) => {
          e.preventDefault();
          setIsDragOver(false);
          if (e.dataTransfer?.files && e.dataTransfer.files.length > 0) {
            const paths: string[] = [];
            for (let i = 0; i < e.dataTransfer.files.length; i++) {
              const file = e.dataTransfer.files[i];
              if ((file as any).path) paths.push((file as any).path);
            }
            if (paths.length > 0) {
              window.flik?.sendDroppedFiles(paths, activeTargetPeer?.deviceId);
            }
          }
        }}
        onClick={handleSendFileToPhone}
      >
        <div style={{ fontSize: 22, marginBottom: 2 }}>📥</div>
        <div style={{ fontSize: 13, fontWeight: 600, color: 'var(--text)' }}>
          {isDragOver ? 'Drop files here!' : 'Drop files or click to send to phone'}
        </div>
        <div style={{ fontSize: 11, color: 'var(--muted)', marginTop: 2 }}>
          {activeTargetPeer
            ? `Ready to stream to ${activeTargetPeer.deviceName}`
            : 'Open Flik on phone to connect'}
        </div>
      </div>

      {/* Send Web Link to Phone */}
      <div
        style={{
          padding: '10px 12px',
          borderRadius: 12,
          background: 'var(--surface)',
          border: '1px solid var(--line)',
          display: 'flex',
          flexDirection: 'column',
          gap: 6,
        }}
      >
        <span style={{ fontSize: 11, color: 'var(--muted)', textTransform: 'uppercase', fontWeight: 600, letterSpacing: 0.5 }}>
          Send Web Link to Phone
        </span>
        <div style={{ display: 'flex', gap: 6 }}>
          <input
            type="text"
            placeholder="https://example.com"
            value={urlToSend}
            onChange={(e) => setUrlToSend(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleSendUrl()}
            style={{
              flex: 1,
              fontSize: 12,
              padding: '6px 10px',
              borderRadius: 8,
              border: '1px solid var(--line)',
              background: 'var(--raised)',
              color: 'var(--text)',
            }}
          />
          <button
            className="btn-pill primary"
            style={{ padding: '6px 12px', fontSize: 11 }}
            onClick={handleSendUrl}
          >
            Send Link
          </button>
        </div>
      </div>

      {/* Bottom Controls */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 4 }}>
        <button
          className="btn-pill primary"
          style={{ width: '100%', height: 36, fontSize: 13 }}
          onClick={handleSendFileToPhone}
        >
          Select File to Send...
        </button>

        <label
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 8,
            fontSize: 12,
            color: 'var(--text)',
            cursor: 'pointer',
            padding: '2px 4px',
          }}
        >
          <input
            type="checkbox"
            checked={startWithWin}
            onChange={toggleStartWithWindows}
          />
          Start with Windows
        </label>
      </div>
    </div>
  );
};
