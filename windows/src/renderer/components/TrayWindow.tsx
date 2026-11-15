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
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    async function loadData() {
      if (window.flik) {
        const devInfo = await window.flik.getDeviceInfo();
        setInfo(devInfo);
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
        <h2 className="tray-title">Flik Connector</h2>
        <div className="status-badge">
          <span className="status-dot"></span>
          Ready for phone
        </div>
      </div>

      <div className="qr-section">
        <canvas ref={canvasRef} className="qr-canvas"></canvas>
        <p className="qr-instruction">
          Scan with Flik on your Android phone to pair instantly on local Wi-Fi.
        </p>
        <span style={{ fontSize: 12, color: 'var(--muted)' }}>
          {info ? `${info.ip}:${info.port}` : 'Detecting network...'}
        </span>
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
