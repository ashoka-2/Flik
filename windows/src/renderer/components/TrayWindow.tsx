import React, { useEffect, useState, useRef } from 'react';
import QRCode from 'qrcode';

interface DeviceInfo {
  deviceId: string;
  deviceName: string;
  ip: string;
  port: number;
  qrPayload: string;
}

export const TrayWindow: React.FC = () => {
  const [info, setInfo] = useState<DeviceInfo | null>(null);
  const [startWithWin, setStartWithWin] = useState<boolean>(false);
  const [peers, setPeers] = useState<any[]>([]);
  const [editingName, setEditingName] = useState<boolean>(false);
  const [deviceName, setDeviceName] = useState<string>('');
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    async function loadData() {
      if (window.flik) {
        const devInfo = await window.flik.getDeviceInfo();
        setInfo(devInfo);
        if (devInfo) {
          setDeviceName(devInfo.deviceName);
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

      <div className="tray-controls">
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
