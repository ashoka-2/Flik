import React, { useEffect, useState } from 'react';
import { FLIK_CONSTANTS } from '../../shared/constants';

interface ToastItem {
  id: string;
  message: string;
  timestamp: number;
}

export const ToastContainer: React.FC = () => {
  const [toasts, setToasts] = useState<ToastItem[]>([]);

  useEffect(() => {
    // Listens for normalized error and status toasts from the main process
    const unsubscribe = window.flik?.onToast((message: string) => {
      setToasts((prev) => {
        const now = Date.now();
        // Deduplicate message if identical toast arrived within 3 seconds
        const duplicate = prev.some(
          (t) => t.message === message && now - t.timestamp < FLIK_CONSTANTS.TOAST_DEDUPE_WINDOW_MS
        );
        if (duplicate) return prev;

        const id = Math.random().toString(36).substring(2, 9);
        return [...prev, { id, message, timestamp: now }];
      });
    });

    return () => {
      if (unsubscribe) unsubscribe();
    };
  }, []);

  // Auto-dismiss each toast after 3.5 seconds
  useEffect(() => {
    if (toasts.length === 0) return;
    const timer = setInterval(() => {
      const now = Date.now();
      setToasts((prev) => prev.filter((t) => now - t.timestamp < FLIK_CONSTANTS.TOAST_AUTO_DISMISS_MS));
    }, 500);

    return () => clearInterval(timer);
  }, [toasts]);

  if (toasts.length === 0) return null;

  return (
    <div className="toast-container" data-interactive="true">
      {toasts.map((t) => (
        <div key={t.id} className="flik-toast">
          {t.message}
        </div>
      ))}
    </div>
  );
};
