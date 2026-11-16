import React, { useState, useRef, useEffect } from 'react';
import { ActiveTransferCard } from '../../shared/types';

interface TransferCardProps {
  card: ActiveTransferCard;
  onPositionChange: (id: string, x: number, y: number) => void;
  onDismiss: (id: string) => void;
}

// Pure floating media component with Apple-grade fluid animations, native drag-out,
// full audio player with controls, video with full-screen escape handling,
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
  const [isPlaying, setIsPlaying] = useState<boolean>(false);
  const [currentTime, setCurrentTime] = useState<number>(0);
  const [duration, setDuration] = useState<number>(0);
  const [isFullscreen, setIsFullscreen] = useState<boolean>(false);

  const ext = firstItem?.name ? firstItem.name.split('.').pop()?.toLowerCase() : '';
  const isVideo = firstItem?.kind === 'video' || firstItem?.mime?.startsWith('video/') || ['mp4', 'mkv', 'mov', 'avi', 'webm'].includes(ext || '');
  const isAudio = firstItem?.kind === 'audio' || firstItem?.mime?.startsWith('audio/') || ['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg'].includes(ext || '');
  const isImage = firstItem?.kind === 'image' || firstItem?.mime?.startsWith('image/') || ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif'].includes(ext || '');

  useEffect(() => {
    let isMounted = true;
    if (firstItem?.localPath && isImage) {
      window.flik?.readMediaDataUrl?.(firstItem.localPath).then((dataUrl) => {
        if (isMounted && dataUrl) {
          setImgSrc(dataUrl);
        }
      });
    }

    const handleEscKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        if (document.fullscreenElement) {
          document.exitFullscreen().catch(() => {});
        }
        setIsFullscreen(false);
      }
    };

    const handleFullscreenChange = () => {
      setIsFullscreen(!!document.fullscreenElement);
    };

    document.addEventListener('keydown', handleEscKey);
    document.addEventListener('fullscreenchange', handleFullscreenChange);

    return () => {
      isMounted = false;
      document.removeEventListener('keydown', handleEscKey);
      document.removeEventListener('fullscreenchange', handleFullscreenChange);
    };
  }, [firstItem?.localPath, isImage]);

  const handlePointerDown = (e: React.PointerEvent) => {
    if ((e.target as HTMLElement).tagName === 'BUTTON' || (e.target as HTMLElement).tagName === 'INPUT') return;
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
    if (dragMoved.current) return;
    // Don't open if clicked control buttons
    if ((e.target as HTMLElement).tagName === 'BUTTON' || (e.target as HTMLElement).tagName === 'INPUT') return;
    if (firstItem?.localPath && !isAudio && !isVideo) {
      window.flik?.openFile(firstItem.localPath);
    }
  };

  const handleContextMenu = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (firstItem?.localPath) {
      window.flik?.showInFolder(firstItem.localPath);
    }
  };

  const handleDragStart = (e: React.DragEvent) => {
    if (card.items.length > 0) {
      e.preventDefault();
      const firstPath = card.items[0].localPath;
      window.flik?.startDrag(firstPath);
    }
  };

  // Video full screen toggle
  const toggleVideoFullscreen = () => {
    if (videoRef.current) {
      if (!document.fullscreenElement) {
        videoRef.current.requestFullscreen().catch(() => {});
        setIsFullscreen(true);
      } else {
        document.exitFullscreen().catch(() => {});
        setIsFullscreen(false);
      }
    }
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
    return `${m}:${s.toString().padLeft ? s.toString().padStart(2, '0') : (s < 10 ? '0' + s : s)}`;
  };

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
      title={`${firstItem?.name || 'Media'} (Right-click to show in folder)`}
    >
      {/* 1. Video Player with Fullscreen / Minimize Controls */}
      {isVideo && firstItem?.localPath && (
        <div style={{ position: 'relative', width: '100%', height: '100%', background: '#000' }}>
          <video
            ref={videoRef}
            src={mediaUrl}
            controls
            autoPlay
            muted
            className="media-content"
            onDoubleClick={toggleVideoFullscreen}
          />
          {isFullscreen && (
            <button
              style={{
                position: 'fixed',
                top: 24,
                right: 24,
                zIndex: 9999,
                background: 'rgba(0, 0, 0, 0.75)',
                color: '#fff',
                border: '1px solid rgba(255, 255, 255, 0.4)',
                borderRadius: 24,
                padding: '8px 18px',
                fontSize: 14,
                fontWeight: 600,
                cursor: 'pointer',
              }}
              onClick={toggleVideoFullscreen}
            >
              ⤢ Exit Fullscreen (Esc)
            </button>
          )}
        </div>
      )}

      {/* 2. Audio Player with Album Artwork, Play/Pause, Rewind, Fast-Forward & Progress */}
      {isAudio && firstItem?.localPath && (
        <div
          style={{
            width: 320,
            padding: 16,
            background: 'linear-gradient(135deg, #181920 0%, #111216 100%)',
            borderRadius: 18,
            border: '1px solid rgba(255, 255, 255, 0.15)',
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
                width: 52,
                height: 52,
                borderRadius: 12,
                background: 'linear-gradient(135deg, #3566EF 0%, #8b5cf6 100%)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: 24,
                boxShadow: '0 8px 16px rgba(53, 102, 239, 0.35)',
              }}
            >
              🎵
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div
                style={{
                  fontSize: 14,
                  fontWeight: 600,
                  whiteSpace: 'nowrap',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                }}
              >
                {firstItem.name}
              </div>
              <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 2 }}>
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
                accentColor: 'var(--accent)',
                cursor: 'pointer',
              }}
            />
            <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 10, color: '#94a3b8' }}>
              <span>{formatTime(currentTime)}</span>
              <span>{formatTime(duration)}</span>
            </div>
          </div>

          {/* Audio Controls */}
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 16 }}>
            <button
              onClick={(e) => seekAudio(-5, e)}
              style={{
                background: 'rgba(255, 255, 255, 0.1)',
                border: 'none',
                borderRadius: '50%',
                width: 32,
                height: 32,
                color: '#fff',
                fontSize: 13,
                cursor: 'pointer',
              }}
              title="Rewind 5s"
            >
              ⏮
            </button>
            <button
              onClick={toggleAudioPlay}
              style={{
                background: 'var(--accent)',
                border: 'none',
                borderRadius: '50%',
                width: 44,
                height: 44,
                color: '#fff',
                fontSize: 18,
                cursor: 'pointer',
                boxShadow: '0 4px 12px rgba(53, 102, 239, 0.4)',
              }}
              title={isPlaying ? 'Pause' : 'Play'}
            >
              {isPlaying ? '⏸' : '▶'}
            </button>
            <button
              onClick={(e) => seekAudio(5, e)}
              style={{
                background: 'rgba(255, 255, 255, 0.1)',
                border: 'none',
                borderRadius: '50%',
                width: 32,
                height: 32,
                color: '#fff',
                fontSize: 13,
                cursor: 'pointer',
              }}
              title="Fast Forward 5s"
            >
              ⏭
            </button>
          </div>
        </div>
      )}

      {/* 3. Photo / Image View */}
      {isImage && (
        <img
          src={mediaUrl}
          alt={firstItem?.name || 'Photo'}
          className="media-content"
          onError={async () => {
            if (firstItem?.localPath && window.flik?.readMediaDataUrl) {
              const url = await window.flik.readMediaDataUrl(firstItem.localPath);
              if (url) setImgSrc(url);
            }
          }}
        />
      )}

      {/* 4. Generic Document / File Card */}
      {!isVideo && !isAudio && !isImage && (
        <div
          style={{
            width: 280,
            padding: 16,
            background: 'var(--surface)',
            borderRadius: 18,
            border: '1px solid var(--line)',
            boxShadow: '0 20px 48px rgba(0, 0, 0, 0.55)',
            display: 'flex',
            alignItems: 'center',
            gap: 12,
            color: '#fff',
          }}
        >
          <div
            style={{
              width: 44,
              height: 44,
              borderRadius: 10,
              background: 'var(--raised)',
              border: '1px solid var(--line)',
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
            <div style={{ fontSize: 11, color: 'var(--muted)', marginTop: 2 }}>
              {firstItem?.size ? `${(firstItem.size / (1024 * 1024)).toFixed(1)} MB` : 'Received File'}
            </div>
          </div>
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
  );
};
