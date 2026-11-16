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

export const TrayWindow: React.FC = () => {
  const [info, setInfo] = useState<DeviceInfo | null>(null);
  const [storagePath, setStoragePath] = useState<string>('');
  const [startWithWin, setStartWithWin] = useState<boolean>(false);
  const [peers, setPeers] = useState<any[]>([]);
  const [editingName, setEditingName] = useState<boolean>(false);
  const [deviceName, setDeviceName] = useState<string>('');
  const [isDragOver, setIsDragOver] = useState<boolean>(false);
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    async function loadData() {
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
        setPeers(discovered);
      }
    }
    loadData();

    const unsubPeers = window.flik?.onPeersUpdated((updated) => setPeers(updated));
    return () => {
      if (unsubPeers) unsubPeers();
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
        width: 160,
        margin: 1,
        color: {
          dark: '#000000',
          light: '#ffffff',
        },
      });
    }
  }, [info]);

  const toggleStartWithWindows = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = e.target.checked;
    setStartWithWin(val);
    await window.flik?.setStartWithWindows(val);
  };

  const handleSendToPhone = async () => {
    if (peers.length > 0) {
      await window.flik?.promptSendFiles(peers[0].deviceId);
    }
  };

  return (
    <div className="tray-shell">
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
                <h2 className="tray-title" style={{ fontSize: 16, lineHeight: 1.2 }}>
                  {deviceName || 'Flik Connector'}
                </h2>
                <span style={{ fontSize: 11, color: 'var(--muted)', textDecoration: 'underline' }}>
                  edit
                </span>
              </div>
            )}
            <div className="status-badge" style={{ marginTop: 2, padding: '2px 8px', fontSize: 11 }}>
              <span className="status-dot"></span>
              Ready for phone
            </div>
          </div>
        </div>

        <button
          className="btn-pill"
          style={{ width: 32, height: 32, padding: 0, fontSize: 14 }}
          title="Minimize to Tray"
          onClick={() => window.flik?.closeDashboard?.()}
        >
          ✕
        </button>
      </div>

      <div className="qr-section">
        <canvas ref={canvasRef} className="qr-canvas"></canvas>
        <p className="qr-instruction">
          Scan with Flik on your Android phone to pair instantly on local Wi-Fi.
        </p>
        <div style={{
          marginTop: 8,
          padding: '6px 12px',
          borderRadius: 8,
          background: 'var(--raised)',
          border: '1px solid var(--line)',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          gap: 2
        }}>
          <span style={{ fontSize: 11, color: 'var(--muted)', textTransform: 'uppercase', letterSpacing: 0.5 }}>
            Wi-Fi Direct / Local IP
          </span>
          <span style={{ fontSize: 14, fontWeight: 700, color: 'var(--accent)', letterSpacing: 0.5 }}>
            {info ? `${info.ip}:${info.port}` : 'Detecting network...'}
          </span>
        </div>
      </div>

      {/* Storage Destination Folder Configuration */}
      <div style={{
        marginTop: 10,
        marginHorizontal: 16,
        padding: '10px 14px',
        borderRadius: 12,
        background: 'var(--raised)',
        border: '1px solid var(--line)',
        display: 'flex',
        flexDirection: 'column',
        gap: 6
      }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span style={{ fontSize: 11, color: 'var(--muted)', textTransform: 'uppercase', fontWeight: 600, letterSpacing: 0.5 }}>
            Save Folder
          </span>
          <button
            className="btn-pill"
            style={{ height: 24, padding: '0 8px', fontSize: 11 }}
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
            textDecoration: 'underline dotted'
          }}
          title={storagePath ? `${storagePath} (Click to open)` : 'Click to select folder'}
          onClick={() => {
            if (storagePath) window.flik?.openFolder(storagePath);
          }}
        >
          📁 {storagePath || 'Loading path...'}
        </div>
      </div>

      {/* Desktop Dropzone for Drag-and-Drop and Multi-file Sending to Phone */}
      <div
        style={{
          marginTop: 10,
          padding: '14px 12px',
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
              window.flik?.sendDroppedFiles(paths, peers[0]?.deviceId);
            }
          }
        }}
        onClick={handleSendToPhone}
      >
        <div style={{ fontSize: 20, marginBottom: 2 }}>📥</div>
        <div style={{ fontSize: 13, fontWeight: 600, color: 'var(--text)' }}>
          {isDragOver ? 'Drop files here!' : 'Drop files or click to send to phone'}
        </div>
        <div style={{ fontSize: 11, color: 'var(--muted)', marginTop: 2 }}>
          {peers.length > 0
            ? `Ready to stream to ${peers[0].deviceName}`
            : 'Open Flik on phone to connect'}
        </div>
      </div>

      <div className="tray-controls" style={{ marginTop: 10 }}>
        <button
          className="btn-pill primary"
          style={{ width: '100%' }}
          onClick={handleSendToPhone}
        >
          Send File to Phone...
        </button>

        <label
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 10,
            fontSize: 13,
            color: 'var(--text)',
            cursor: 'pointer',
            padding: '8px 4px',
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
