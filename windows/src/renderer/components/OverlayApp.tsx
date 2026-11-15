import React, { useEffect, useState, useRef, useCallback } from 'react';
import { ActiveTransferCard, InteractiveRect } from '../../shared/types';
import { TransferCard } from './TransferCard';
import { CardDeck } from './CardDeck';
import { PairingModal } from './PairingModal';
import { ToastContainer } from './ToastContainer';

interface PendingPairing {
  id: string;
  deviceId: string;
  deviceName: string;
  code: string;
}

export const OverlayApp: React.FC = () => {
  const [cards, setCards] = useState<ActiveTransferCard[]>([]);
  const [isGrouped, setIsGrouped] = useState<boolean>(false);
  const [pairingRequest, setPairingRequest] = useState<PendingPairing | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  // Computes interactive bounding boxes and reports them to Electron main for 60Hz cursor click-through
  const reportRects = useCallback(() => {
    if (!containerRef.current) return;
    const elements = containerRef.current.querySelectorAll('[data-interactive="true"]');
    const rects: InteractiveRect[] = [];

    elements.forEach((el, index) => {
      const box = el.getBoundingClientRect();
      if (box.width > 0 && box.height > 0) {
        rects.push({
          id: `rect-${index}`,
          x: Math.round(box.left),
          y: Math.round(box.top),
          width: Math.round(box.width),
          height: Math.round(box.height),
        });
      }
    });

    window.flik?.reportInteractiveRects(rects);
  }, []);

  // Syncs rects whenever cards, groups, or pairing dialog changes
  useEffect(() => {
    reportRects();
    const interval = setInterval(reportRects, 200);
    return () => clearInterval(interval);
  }, [cards, isGrouped, pairingRequest, reportRects]);

  useEffect(() => {
    // Listen for incoming transfer cards
    const unsubTransfer = window.flik?.onTransferReceived((newCard: ActiveTransferCard) => {
      // Calculate screen landing position from trajectoryX (-1.0 to 1.0 or 0.0 to 1.0)
      const traj = typeof newCard.trajectoryX === 'number' ? newCard.trajectoryX : 0;
      const normalizedTraj = traj >= -1 && traj <= 1 ? traj : 0;
      const targetX = Math.max(
        40,
        Math.min(window.innerWidth - 320, window.innerWidth * 0.5 + normalizedTraj * (window.innerWidth * 0.35) - 140)
      );
      const targetY = Math.max(80, window.innerHeight * 0.45);

      const placedCard = {
        ...newCard,
        x: targetX,
        y: targetY,
      };

      setCards((prev) => [...prev, placedCard]);
    });

    // Listen for incoming pairing request modal
    const unsubPairing = window.flik?.onPairingRequest((request: PendingPairing) => {
      setPairingRequest(request);
    });

    // Keyboard shortcut: Ctrl+G to group all cards together
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && (e.key === 'g' || e.key === 'G')) {
        e.preventDefault();
        setIsGrouped((prev) => !prev);
      }
    };
    window.addEventListener('keydown', handleKeyDown);

    return () => {
      if (unsubTransfer) unsubTransfer();
      if (unsubPairing) unsubPairing();
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, []);

  const handlePositionChange = (id: string, x: number, y: number) => {
    setCards((prev) =>
      prev.map((c) => (c.id === id ? { ...c, x, y } : c))
    );
  };

  const handleDismissCard = (id: string) => {
    setCards((prev) => prev.filter((c) => c.id !== id));
  };

  const handleDeleteGroup = (groupedCards: ActiveTransferCard[]) => {
    const ids = new Set(groupedCards.map((c) => c.id));
    setCards((prev) => prev.filter((c) => !ids.has(c.id)));
    setIsGrouped(false);
  };

  const handlePairingResponse = (accept: boolean) => {
    if (pairingRequest) {
      window.flik?.respondPairing(pairingRequest.id, accept);
      setPairingRequest(null);
    }
  };

  return (
    <div ref={containerRef} className="overlay-container">
      {/* Active transfer cards or stacked deck */}
      {isGrouped && cards.length > 1 ? (
        <CardDeck
          cards={cards}
          onSpread={() => setIsGrouped(false)}
          onDeleteGroup={handleDeleteGroup}
          onPositionChange={handlePositionChange}
          onDismissSingle={handleDismissCard}
        />
      ) : (
        cards.map((card) => (
          <TransferCard
            key={card.id}
            card={card}
            onPositionChange={handlePositionChange}
            onDismiss={handleDismissCard}
          />
        ))
      )}

      {/* Pairing approval modal dialog */}
      {pairingRequest && (
        <PairingModal request={pairingRequest} onRespond={handlePairingResponse} />
      )}

      {/* Normalized error toasts */}
      <ToastContainer />
    </div>
  );
};
