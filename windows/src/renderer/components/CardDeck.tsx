import React, { useState } from 'react';
import { ActiveTransferCard } from '../../shared/types';
import { TransferCard } from './TransferCard';

interface CardDeckProps {
  cards: ActiveTransferCard[];
  onSpread: () => void;
  onDeleteGroup: (cards: ActiveTransferCard[]) => void;
  onPositionChange: (id: string, x: number, y: number) => void;
  onDismissSingle: (id: string) => void;
}

export const CardDeck: React.FC<CardDeckProps> = ({
  cards,
  onSpread,
  onDeleteGroup,
  onPositionChange,
  onDismissSingle,
}) => {
  const [isSpread, setIsSpread] = useState(false);

  if (cards.length === 0) return null;

  const totalFiles = cards.reduce((acc, c) => acc + c.items.length, 0);
  const baseCard = cards[0];

  const handleSaveAll = async () => {
    const allPaths: string[] = [];
    for (const c of cards) {
      for (const item of c.items) {
        allPaths.push(item.localPath);
      }
    }
    await window.flik?.saveFilesToFolder(allPaths);
  };

  const handleDeleteAll = () => {
    const allPaths: string[] = [];
    for (const c of cards) {
      for (const item of c.items) {
        allPaths.push(item.localPath);
      }
    }
    window.flik?.deleteFiles(allPaths);
    onDeleteGroup(cards);
  };

  const toggleSpread = () => {
    setIsSpread(!isSpread);
    onSpread();
  };

  if (isSpread) {
    return (
      <>
        {cards.map((c, idx) => (
          <TransferCard
            key={c.id}
            card={{
              ...c,
              x: Math.min(window.innerWidth - 300, baseCard.x + idx * 300),
              y: baseCard.y,
            }}
            onPositionChange={onPositionChange}
            onDismiss={onDismissSingle}
          />
        ))}
      </>
    );
  }

  return (
    <div
      className="stacked-deck interactive"
      data-interactive="true"
      style={{
        transform: `translate3d(${baseCard.x}px, ${baseCard.y}px, 0)`,
      }}
    >
      <div className="deck-count-badge">{totalFiles}</div>

      {/* Render stacked cards with slight offset depth */}
      {cards.slice(0, 3).map((c, i) => (
        <div
          key={c.id}
          style={{
            position: 'absolute',
            top: i * -6,
            left: i * 6,
            zIndex: 10 - i,
            opacity: 1 - i * 0.15,
            pointerEvents: i === 0 ? 'auto' : 'none',
          }}
        >
          <TransferCard
            card={{ ...c, x: 0, y: 0 }}
            onPositionChange={(_id, newX, newY) => onPositionChange(baseCard.id, baseCard.x + newX, baseCard.y + newY)}
            onDismiss={onDismissSingle}
          />
        </div>
      ))}

      {/* "X together." Toolbar */}
      <div className="deck-toolbar" data-interactive="true">
        <span className="deck-label">{totalFiles} together.</span>
        <button className="btn-pill primary" style={{ height: 32, fontSize: 12 }} onClick={handleSaveAll}>
          Save folder...
        </button>
        <button className="btn-pill" style={{ height: 32, fontSize: 12 }} onClick={toggleSpread}>
          Spread
        </button>
        <button className="btn-pill danger" style={{ height: 32, fontSize: 12 }} onClick={handleDeleteAll}>
          Delete
        </button>
      </div>
    </div>
  );
};
