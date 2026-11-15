import React from 'react';

interface PairingRequestData {
  id: string;
  deviceId: string;
  deviceName: string;
  code: string;
}

interface PairingModalProps {
  request: PairingRequestData;
  onRespond: (accept: boolean) => void;
}

export const PairingModal: React.FC<PairingModalProps> = ({ request, onRespond }) => {
  return (
    <div className="modal-backdrop" data-interactive="true">
      <div className="pairing-dialog" data-interactive="true">
        <h2 className="pairing-title">Connect with Phone?</h2>
        <p className="pairing-device-name">{request.deviceName}</p>

        <div className="pairing-code-box">
          <div className="pairing-code">{request.code}</div>
        </div>

        <div className="pairing-actions">
          <button className="btn-pill" onClick={() => onRespond(false)}>
            Not now
          </button>
          <button className="btn-pill primary" onClick={() => onRespond(true)}>
            Accept
          </button>
        </div>
      </div>
    </div>
  );
};
