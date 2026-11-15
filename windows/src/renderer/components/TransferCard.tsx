import React, { useState, useRef } from 'react';
import { ActiveTransferCard } from '../../shared/types';

interface TransferCardProps {
  card: ActiveTransferCard;
  onPositionChange: (id: string, x: number, y: number) => void;
  onDismiss: (id: string) => void;
}

export const TransferCard: React.FC<TransferCardProps> = ({ card, onPositionChange, onDismiss }) => {
  const [isDragging, setIsDragging] = useState(false);
  const dragOffset = useRef({ x: 0, y: 0 });
  const cardRef = useRef<HTMLDivElement>(null);

  const handlePointerDown = (e: React.PointerEvent) => {
    // Prevent dragging when clicking interactive buttons
    if ((e.target as HTMLElement).tagName === 'BUTTON') return;

    setIsDragging(true);
    dragOffset.current = {
      x: e.clientX - card.x,
      y: e.clientY - card.y,
    };
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
  };

  const handlePointerMove = (e: React.PointerEvent) => {
    if (!isDragging) return;
    const newX = Math.max(10, Math.min(window.innerWidth - 300, e.clientX - dragOffset.current.x));
    const newY = Math.max(10, Math.min(window.innerHeight - 200, e.clientY - dragOffset.current.y));
    onPositionChange(card.id, newX, newY);
  };

  const handlePointerUp = (e: React.PointerEvent) => {
    if (isDragging) {
      setIsDragging(false);
      try {
        (e.target as HTMLElement).releasePointerCapture(e.pointerId);
      } catch {}
    }
  };

  // Initiates native Windows drag-out to desktop, file explorer, or apps
  const handleDragStart = (e: React.DragEvent) => {
    if (card.items.length > 0) {
      e.preventDefault();
      const firstPath = card.items[0].localPath;
      window.flik?.startDrag(firstPath);
    }
  };

  const firstItem = card.items[0];
  const sizeMb = firstItem ? (firstItem.size / (1024 * 1024)).toFixed(1) : '0';

  const getItemIcon = (kind: string) => {
    switch (kind) {
      case 'image':
        return '📷';
      case 'video':
        return '🎬';
      default:
        return '📄';
    }
  };

  return (
    <div
      ref={cardRef}
      className="flik-card interactive flying-in"
      data-interactive="true"
      style={{
        transform: `translate3d(${card.x}px, ${card.y}px, 0)`,
      }}
      draggable
      onDragStart={handleDragStart}
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerUp}
    >
      <div className="card-header">
        <span className="sender-pill">{card.senderName}</span>
        <button
          className="btn-pill"
          style={{ height: 28, padding: '0 8px', fontSize: 11 }}
          onClick={() => onDismiss(card.id)}
        >
          ✕
        </button>
      </div>

      <div className="item-preview">
        <div className="item-icon-box">{getItemIcon(firstItem?.kind || 'file')}</div>
        <div className="item-info">
          <span className="item-name" title={firstItem?.name}>
            {firstItem?.name || 'Untitled File'}
          </span>
          <span className="item-meta">
            {card.items.length > 1
              ? `${card.items.length} files · ${sizeMb} MB`
              : `${sizeMb} MB · ${firstItem?.kind || 'file'}`}
          </span>
        </div>
      </div>

      <div className="card-actions">
        <button
          className="btn-pill primary"
          style={{ flex: 1, height: 36 }}
          onClick={() => {
            if (firstItem?.localPath) {
              window.flik?.openFolder(firstItem.localPath);
            }
          }}
        >
          Open
        </button>
        <button
          className="btn-pill"
          style={{ flex: 1, height: 36 }}
          onClick={async () => {
            const paths = card.items.map((i) => i.localPath);
            await window.flik?.saveFilesToFolder(paths);
          }}
        >
          Save
        </button>
      </div>
    </div>
  );
};
