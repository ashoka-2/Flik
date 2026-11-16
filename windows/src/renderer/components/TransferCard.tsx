import React, { useState, useRef, useEffect } from 'react';
import { ActiveTransferCard } from '../../shared/types';

interface TransferCardProps {
  card: ActiveTransferCard;
  onPositionChange: (id: string, x: number, y: number) => void;
  onDismiss: (id: string) => void;
}

// Pure floating media component with Apple-grade fluid animations, native drag-out,
// left-click open, right-click reveal in File Explorer, and zero clunky wrapper box.
export const TransferCard: React.FC<TransferCardProps> = ({ card, onPositionChange, onDismiss }) => {
  const [isDragging, setIsDragging] = useState(false);
  const dragOffset = useRef({ x: 0, y: 0 });
  const cardRef = useRef<HTMLDivElement>(null);
  const dragMoved = useRef(false);

  const firstItem = card.items[0];
  const [imgSrc, setImgSrc] = useState<string>('');

  useEffect(() => {
    let isMounted = true;
    if (firstItem?.localPath) {
      // Instantly load base64 data URL via IPC with on-the-fly HEIC decoding
      window.flik?.readMediaDataUrl?.(firstItem.localPath).then((dataUrl) => {
        if (isMounted && dataUrl) {
          setImgSrc(dataUrl);
        }
      });
    }
    return () => {
      isMounted = false;
    };
  }, [firstItem?.localPath]);

  const handleImgError = async () => {
    if (firstItem?.localPath && window.flik?.readMediaDataUrl) {
      const dataUrl = await window.flik.readMediaDataUrl(firstItem.localPath);
      if (dataUrl) {
        setImgSrc(dataUrl);
      }
    }
  };

  const handlePointerDown = (e: React.PointerEvent) => {
    // If clicking close button or video controls, do not drag
    if ((e.target as HTMLElement).tagName === 'BUTTON' || (e.target as HTMLElement).tagName === 'VIDEO') return;

    setIsDragging(true);
    dragMoved.current = false;
    dragOffset.current = {
      x: e.clientX - card.x,
      y: e.clientY - card.y,
    };
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
  };

  const handlePointerMove = (e: React.PointerEvent) => {
    if (!isDragging) return;
    dragMoved.current = true;
    const newX = Math.max(10, Math.min(window.innerWidth - 200, e.clientX - dragOffset.current.x));
    const newY = Math.max(10, Math.min(window.innerHeight - 150, e.clientY - dragOffset.current.y));
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

  // Left-click opens the image or video directly in default Windows viewer
  const handleClick = (e: React.MouseEvent) => {
    if (dragMoved.current) return;
    if (firstItem?.localPath) {
      window.flik?.openFile(firstItem.localPath);
    }
  };

  // Right-click reveals and highlights the file inside File Explorer
  const handleContextMenu = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (firstItem?.localPath) {
      window.flik?.showInFolder(firstItem.localPath);
    }
  };

  // Native Windows drag-out into desktop, Photoshop, Discord, or folders
  const handleDragStart = (e: React.DragEvent) => {
    if (card.items.length > 0) {
      e.preventDefault();
      const firstPath = card.items[0].localPath;
      window.flik?.startDrag(firstPath);
    }
  };

  const isVideo = firstItem?.kind === 'video' || firstItem?.mime?.startsWith('video/');
  const mediaUrl = imgSrc || (firstItem?.localPath ? `http://127.0.0.1:54321/media?file=${encodeURIComponent(firstItem.localPath)}` : '');

  return (
    <div
      ref={cardRef}
      className="flik-floating-media interactive flying-in"
      data-interactive="true"
      style={{
        left: `${card.x}px`,
        top: `${card.y}px`,
      }}
      draggable
      onDragStart={handleDragStart}
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerUp}
      onClick={handleClick}
      onContextMenu={handleContextMenu}
      title={`${firstItem?.name || 'Media'} (Left-click to open, Right-click to show in folder)`}
    >
      {/* Pure Media: Video Player or Picture */}
      {isVideo && firstItem?.localPath ? (
        <video
          src={`http://127.0.0.1:54321/media?file=${encodeURIComponent(firstItem.localPath)}`}
          controls
          autoPlay
          muted
          className="media-content"
        />
      ) : (
        <img
          src={mediaUrl}
          alt={firstItem?.name || 'Photo'}
          className="media-content"
          onError={handleImgError}
        />
      )}

      {/* Floating subtle dismiss button on hover */}
      <button
        className="floating-dismiss-btn"
        title="Dismiss from screen"
        onClick={(e) => {
          e.stopPropagation();
          onDismiss(card.id);
        }}
      >
        ✕
      </button>
    </div>
  );
};
