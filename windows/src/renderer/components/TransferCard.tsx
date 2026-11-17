import React, { useState, useRef, useEffect } from 'react';
import { ActiveTransferCard } from '../../shared/types';

interface TransferCardProps {
  card: ActiveTransferCard;
  onPositionChange: (id: string, x: number, y: number) => void;
  onDismiss: (id: string) => void;
}

// Pure floating media component with Apple-grade fluid animations, native drag-out,
// minimal-ai-ui styled audio player with controls, video with reliable theater maximize/minimize escape handling,
// resilient image rendering with automatic HEIC decoding & graceful fallback,
// left-click open, right-click reveal in File Explorer, and zero broken image placeholders.
export const TransferCard: React.FC<TransferCardProps> = ({ card, onPositionChange, onDismiss }) => {
  const [isDragging, setIsDragging] = useState(false);
  const dragOffset = useRef({ x: 0, y: 0 });
  const cardRef = useRef<HTMLDivElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const audioRef = useRef<HTMLAudioElement>(null);
  const dragMoved = useRef(false);

  const firstItem = card.items[0];
  const [imgSrc, setImgSrc] = useState<string>('');
  const [imgError, setImgError] = useState<boolean>(false);
  const [isPlaying, setIsPlaying] = useState<boolean>(false);
  const [currentTime, setCurrentTime] = useState<number>(0);
  const [duration, setDuration] = useState<number>(0);
  const [isExpandedVideo, setIsExpandedVideo] = useState<boolean>(false);
  const [contextMenuPos, setContextMenuPos] = useState<{ x: number; y: number } | null>(null);

  const ext = firstItem?.name ? firstItem.name.split('.').pop()?.toLowerCase() : '';
  const isVideo = firstItem?.kind === 'video' || firstItem?.mime?.startsWith('video/') || ['mp4', 'mkv', 'mov', 'avi', 'webm', '3gp'].includes(ext || '');
  const isAudio = firstItem?.kind === 'audio' || firstItem?.mime?.startsWith('audio/') || ['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg', 'opus'].includes(ext || '');
  const isImage = firstItem?.kind === 'image' || firstItem?.mime?.startsWith('image/') || ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif'].includes(ext || '');

  useEffect(() => {
    let isMounted = true;
    if (firstItem?.localPath && isImage) {
      window.flik?.readMediaDataUrl?.(firstItem.localPath).then((dataUrl) => {
        if (isMounted) {
          if (dataUrl) {
            setImgSrc(dataUrl);
            setImgError(false);
          } else {
            setImgError(true);
          }
        }
      }).catch(() => {
        if (isMounted) setImgError(true);
      });
    }

    const handleEscKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        if (contextMenuPos) {
          setContextMenuPos(null);
          return;
        }
        if (isExpandedVideo) {
          setIsExpandedVideo(false);
          window.flik?.setFullscreenMode?.(false);
          return;
        }
        if (document.fullscreenElement) {
          document.exitFullscreen().catch(() => {});
        }
      }
    };

    window.addEventListener('keydown', handleEscKey);
    return () => {
      isMounted = false;
      window.removeEventListener('keydown', handleEscKey);
    };
  }, [firstItem?.localPath, isImage, isExpandedVideo, ext, contextMenuPos]);

  // Handle IPC forced exit fullscreen (e.g. from global Escape hook)
  useEffect(() => {
    const unsub = window.flik?.onForceExitFullscreen?.(() => {
      if (isExpandedVideo) {
        setIsExpandedVideo(false);
        window.flik?.setFullscreenMode?.(false);
      }
    });
    return () => {
      unsub?.();
      if (isExpandedVideo) {
        window.flik?.setFullscreenMode?.(false);
      }
    };
  }, [isExpandedVideo]);

  // Click outside to dismiss context menu
  useEffect(() => {
    if (!contextMenuPos) return;
    const handleOutsideClick = (e: MouseEvent | PointerEvent) => {
      if (cardRef.current && !cardRef.current.contains(e.target as Node)) {
        setContextMenuPos(null);
      }
    };
    window.addEventListener('pointerdown', handleOutsideClick);
    return () => window.removeEventListener('pointerdown', handleOutsideClick);
  }, [contextMenuPos]);

  const handlePointerDown = (e: React.PointerEvent) => {
    if ((e.target as HTMLElement).tagName === 'BUTTON' || (e.target as HTMLElement).tagName === 'INPUT' || (e.target as HTMLElement).closest('.flik-context-menu')) return;
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

  const handleClick = (e: React.MouseEvent) => {
    if (contextMenuPos) {
      setContextMenuPos(null);
      return;
    }
    if (dragMoved.current) return;
    // Don't open if clicked interactive control buttons or context menu
    if ((e.target as HTMLElement).closest('button') || (e.target as HTMLElement).tagName === 'INPUT' || (e.target as HTMLElement).closest('.flik-context-menu')) return;
    if (firstItem?.localPath && !isAudio && !isVideo) {
      window.flik?.openFile(firstItem.localPath);
    }
  };

  const handleContextMenu = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    const rect = cardRef.current?.getBoundingClientRect();
    if (rect) {
      const posX = Math.max(8, Math.min(rect.width - 180, e.clientX - rect.left));
      const posY = Math.max(8, Math.min(rect.height - 140, e.clientY - rect.top));
      setContextMenuPos({ x: posX, y: posY });
    } else {
      setContextMenuPos({ x: 12, y: 12 });
    }
  };

  const handleCopyImage = async (e: React.MouseEvent) => {
    e.stopPropagation();
    setContextMenuPos(null);
    if (firstItem?.localPath) {
      await window.flik?.copyImage(firstItem.localPath);
    }
  };

  const handleViewInFolder = (e: React.MouseEvent) => {
    e.stopPropagation();
    setContextMenuPos(null);
    if (firstItem?.localPath) {
      window.flik?.showInFolder(firstItem.localPath);
    }
  };

  const handleDelete = (e: React.MouseEvent) => {
    e.stopPropagation();
    setContextMenuPos(null);
    if (firstItem?.localPath) {
      window.flik?.deleteFiles([firstItem.localPath]);
    }
    onDismiss(card.id);
  };

  const handleDragStart = (e: React.DragEvent) => {
    if (card.items.length > 0) {
      e.preventDefault();
      const firstPath = card.items[0].localPath;
      window.flik?.startDrag(firstPath);
    }
  };

  // Video expand / theater toggle
  const toggleVideoExpand = (e?: React.MouseEvent) => {
    e?.stopPropagation();
    setIsExpandedVideo((prev) => {
      const next = !prev;
      window.flik?.setFullscreenMode?.(next);
      return next;
    });
  };

  const handleExitExpanded = (e?: React.MouseEvent) => {
    e?.stopPropagation();
    setIsExpandedVideo(false);
    window.flik?.setFullscreenMode?.(false);
  };

  // Audio Playback Controls
  const toggleAudioPlay = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (audioRef.current) {
      if (isPlaying) {
        audioRef.current.pause();
        setIsPlaying(false);
      } else {
        audioRef.current.play().catch(() => {});
        setIsPlaying(true);
      }
    }
  };

  const seekAudio = (secondsOffset: number, e: React.MouseEvent) => {
    e.stopPropagation();
    if (audioRef.current) {
      audioRef.current.currentTime = Math.max(0, Math.min(duration, audioRef.current.currentTime + secondsOffset));
    }
  };

  const formatTime = (seconds: number) => {
    if (isNaN(seconds) || seconds <= 0) return '0:00';
    const m = Math.floor(seconds / 60);
    const s = Math.floor(seconds % 60);
    return `${m}:${s < 10 ? '0' + s : s}`;
  };

  const mediaUrl = imgSrc || (firstItem?.localPath ? `http://127.0.0.1:54321/media?file=${encodeURIComponent(firstItem.localPath)}` : '');

  return (
    <>
      {/* Expanded Theater Video View */}
      {isExpandedVideo && isVideo && (
        <div
          data-interactive="true"
          style={{
            position: 'fixed',
            inset: 0,
            zIndex: 99999,
            backgroundColor: 'rgba(0, 0, 0, 0.94)',
            backdropFilter: 'blur(24px)',
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            padding: 32,
            cursor: 'default',
          }}
          onClick={handleExitExpanded}
        >
          {/* Top Control Bar */}
          <div
            style={{
              position: 'absolute',
              top: 24,
              right: 32,
              display: 'flex',
              alignItems: 'center',
              gap: 14,
              zIndex: 100000,
            }}
            onClick={(e) => e.stopPropagation()}
          >
            <button
              onClick={handleExitExpanded}
              style={{
                background: 'rgba(255, 255, 255, 0.16)',
                color: '#fff',
                border: '1px solid rgba(255, 255, 255, 0.35)',
                borderRadius: 999,
                padding: '10px 22px',
                fontSize: 14,
                fontWeight: 600,
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: 8,
                boxShadow: '0 8px 24px rgba(0, 0, 0, 0.6)',
              }}
              title="Minimize to Desktop (Esc)"
            >
              <span>⤢</span> Minimize (Esc)
            </button>
            <button
              onClick={(e) => {
                e.stopPropagation();
                handleExitExpanded();
                onDismiss(card.id);
              }}
              style={{
                background: 'rgba(239, 68, 68, 0.85)',
                color: '#fff',
                border: 'none',
                borderRadius: '50%',
                width: 40,
                height: 40,
                fontSize: 18,
                fontWeight: 700,
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                boxShadow: '0 8px 24px rgba(239, 68, 68, 0.4)',
              }}
              title="Close and Dismiss Video"
            >
              ✕
            </button>
          </div>

          {/* Video Container */}
          <div
            style={{
              maxWidth: '90vw',
              maxHeight: '82vh',
              borderRadius: 20,
              overflow: 'hidden',
              boxShadow: '0 32px 80px rgba(0, 0, 0, 0.95), 0 0 0 1px rgba(255, 255, 255, 0.15)',
              background: '#000000',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}
            onClick={(e) => e.stopPropagation()}
          >
            <video
              src={mediaUrl}
              controls
              autoPlay
              controlsList="nodownload nofullscreen"
              onDoubleClick={handleExitExpanded}
              style={{
                maxWidth: '90vw',
                maxHeight: '82vh',
                display: 'block',
                borderRadius: 20,
                outline: 'none',
              }}
            />
          </div>
        </div>
      )}

      {/* Normal Floating Card */}
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
        title={`${firstItem?.name || 'Media'} (Right-click to show in folder)`}
      >
        {/* 1. Video Player with Theater Expand / Fullscreen & Play Controls */}
        {isVideo && firstItem?.localPath && (
          <div style={{ position: 'relative', width: '100%', height: '100%', background: '#000', borderRadius: 18, overflow: 'hidden' }}>
            <video
              ref={videoRef}
              src={mediaUrl}
              controls
              autoPlay
              muted
              controlsList="nodownload nofullscreen"
              className="media-content"
              onDoubleClick={toggleVideoExpand}
            />
            <button
              style={{
                position: 'absolute',
                top: 8,
                left: 8,
                zIndex: 10,
                background: 'rgba(0, 0, 0, 0.65)',
                color: '#fff',
                border: '1px solid rgba(255, 255, 255, 0.3)',
                borderRadius: 999,
                padding: '4px 10px',
                fontSize: 11,
                fontWeight: 600,
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: 4,
              }}
              onClick={toggleVideoExpand}
              title="Expand to Theater View"
            >
              ⤢ Expand
            </button>
          </div>
        )}

        {/* 2. Audio Player conforming to minimal-ai-ui (neutral surfaces, #3566EF accent, pill geometry) */}
        {isAudio && firstItem?.localPath && (
          <div
            style={{
              width: 310,
              padding: 16,
              background: '#151515',
              borderRadius: 20,
              border: '1px solid rgba(255, 255, 255, 0.08)',
              boxShadow: '0 20px 48px rgba(0, 0, 0, 0.65)',
              display: 'flex',
              flexDirection: 'column',
              gap: 12,
              color: '#fff',
            }}
          >
            <audio
              ref={audioRef}
              src={mediaUrl}
              onTimeUpdate={() => audioRef.current && setCurrentTime(audioRef.current.currentTime)}
              onLoadedMetadata={() => audioRef.current && setDuration(audioRef.current.duration)}
              onEnded={() => setIsPlaying(false)}
            />

            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <div
                style={{
                  width: 44,
                  height: 44,
                  borderRadius: 12,
                  background: 'rgba(53, 102, 239, 0.15)',
                  border: '1px solid rgba(53, 102, 239, 0.35)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: 22,
                }}
              >
                🎵
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div
                  style={{
                    fontSize: 13,
                    fontWeight: 600,
                    whiteSpace: 'nowrap',
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                  }}
                >
                  {firstItem.name}
                </div>
                <div style={{ fontSize: 11, color: '#888', marginTop: 2 }}>
                  Audio Track • {(firstItem.size / (1024 * 1024)).toFixed(1)} MB
                </div>
              </div>
            </div>

            {/* Progress Slider */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
              <input
                type="range"
                min={0}
                max={duration || 100}
                value={currentTime}
                onChange={(e) => {
                  const val = Number(e.target.value);
                  setCurrentTime(val);
                  if (audioRef.current) audioRef.current.currentTime = val;
                }}
                style={{
                  width: '100%',
                  height: 4,
                  accentColor: '#3566EF',
                  cursor: 'pointer',
                }}
              />
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 10, color: '#888' }}>
                <span>{formatTime(currentTime)}</span>
                <span>{formatTime(duration)}</span>
              </div>
            </div>

            {/* Minimal AI UI Audio Controls (Pill Geometry) */}
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 12 }}>
              <button
                onClick={(e) => seekAudio(-5, e)}
                style={{
                  background: '#20201E',
                  border: '1px solid rgba(255, 255, 255, 0.08)',
                  borderRadius: 999,
                  width: 32,
                  height: 32,
                  color: '#fff',
                  fontSize: 12,
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                }}
                title="Rewind 5s"
              >
                ⏮
              </button>
              <button
                onClick={toggleAudioPlay}
                style={{
                  background: '#3566EF',
                  border: 'none',
                  borderRadius: 999,
                  width: 42,
                  height: 42,
                  color: '#fff',
                  fontSize: 16,
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  boxShadow: '0 4px 14px rgba(53, 102, 239, 0.45)',
                }}
                title={isPlaying ? 'Pause' : 'Play'}
              >
                {isPlaying ? '⏸' : '▶'}
              </button>
              <button
                onClick={(e) => seekAudio(5, e)}
                style={{
                  background: '#20201E',
                  border: '1px solid rgba(255, 255, 255, 0.08)',
                  borderRadius: 999,
                  width: 32,
                  height: 32,
                  color: '#fff',
                  fontSize: 12,
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                }}
                title="Fast Forward 5s"
              >
                ⏭
              </button>
            </div>
          </div>
        )}

        {/* 3. Photo / Image View - Resilient with HEIC conversion and Fallback */}
        {isImage && !imgError && mediaUrl && (
          <img
            src={mediaUrl}
            alt=""
            className="media-content"
            onError={() => {
              setImgError(true);
            }}
          />
        )}

        {/* 3b. Fallback Card if Image Failed or is HEIC not decoded in browser */}
        {isImage && (imgError || !mediaUrl) && (
          <div
            style={{
              width: 280,
              padding: 16,
              background: '#151515',
              borderRadius: 18,
              border: '1px solid rgba(255, 255, 255, 0.1)',
              boxShadow: '0 20px 48px rgba(0, 0, 0, 0.65)',
              display: 'flex',
              flexDirection: 'column',
              gap: 12,
              color: '#fff',
              cursor: 'pointer',
            }}
            onClick={() => firstItem?.localPath && window.flik?.openFile(firstItem.localPath)}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <div
                style={{
                  width: 44,
                  height: 44,
                  borderRadius: 12,
                  background: 'rgba(53, 102, 239, 0.15)',
                  border: '1px solid rgba(53, 102, 239, 0.35)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: 22,
                }}
              >
                🖼️
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div
                  style={{
                    fontSize: 13,
                    fontWeight: 600,
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap',
                  }}
                >
                  {firstItem?.name || 'Image'}
                </div>
                <div style={{ fontSize: 11, color: '#888', marginTop: 2 }}>
                  {firstItem?.size ? `${(firstItem.size / (1024 * 1024)).toFixed(1)} MB • ` : ''}
                  {ext.toUpperCase()} Photo
                </div>
              </div>
            </div>

            <button
              style={{
                width: '100%',
                padding: '8px 12px',
                borderRadius: 999,
                background: '#3566EF',
                border: 'none',
                color: '#fff',
                fontSize: 12,
                fontWeight: 600,
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: 6,
                boxShadow: '0 4px 12px rgba(53, 102, 239, 0.35)',
              }}
              onClick={(e) => {
                e.stopPropagation();
                if (firstItem?.localPath) window.flik?.openFile(firstItem.localPath);
              }}
            >
              <span>👁️</span> Click to view photo
            </button>
          </div>
        )}

        {/* 4. Generic Document / File Card */}
        {!isVideo && !isAudio && !isImage && (
          <div
            style={{
              width: 280,
              padding: 16,
              background: '#151515',
              borderRadius: 18,
              border: '1px solid rgba(255, 255, 255, 0.1)',
              boxShadow: '0 20px 48px rgba(0, 0, 0, 0.55)',
              display: 'flex',
              alignItems: 'center',
              gap: 12,
              color: '#fff',
              cursor: 'pointer',
            }}
            onClick={() => firstItem?.localPath && window.flik?.openFile(firstItem.localPath)}
          >
            <div
              style={{
                width: 44,
                height: 44,
                borderRadius: 10,
                background: '#20201E',
                border: '1px solid rgba(255, 255, 255, 0.08)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: 20,
              }}
            >
              📄
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div
                style={{
                  fontSize: 13,
                  fontWeight: 600,
                  whiteSpace: 'nowrap',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                }}
              >
                {firstItem?.name || 'File'}
              </div>
              <div style={{ fontSize: 11, color: '#888', marginTop: 2 }}>
                {firstItem?.size ? `${(firstItem.size / (1024 * 1024)).toFixed(1)} MB` : 'Received File'}
              </div>
            </div>
          </div>
        )}

        {/* Context Menu Dropdown */}
        {contextMenuPos && (
          <div
            className="flik-context-menu"
            style={{
              left: `${contextMenuPos.x}px`,
              top: `${contextMenuPos.y}px`,
            }}
            onClick={(e) => e.stopPropagation()}
          >
            {isImage && (
              <button className="flik-context-menu-item" onClick={handleCopyImage}>
                <span>📋</span> Copy Image
              </button>
            )}
            <button className="flik-context-menu-item" onClick={handleViewInFolder}>
              <span>📁</span> View in Folder
            </button>
            <div className="flik-context-menu-divider" />
            <button className="flik-context-menu-item danger" onClick={handleDelete}>
              <span>🗑️</span> Delete
            </button>
          </div>
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
    </>
  );
};
