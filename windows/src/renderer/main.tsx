import React from 'react';
import { createRoot } from 'react-dom/client';
import { OverlayApp } from './components/OverlayApp';
import { TrayWindow } from './components/TrayWindow';
import { FlikApi } from '../preload/preload';
import './style.css';

declare global {
  interface Window {
    flik?: FlikApi;
  }
}

// Inspect query parameters to decide whether to mount Overlay or Tray window
const params = new URLSearchParams(window.location.search);
const mode = params.get('mode');

const rootElement = document.getElementById('root');
if (rootElement) {
  const root = createRoot(rootElement);
  if (mode === 'tray') {
    root.render(
      <React.StrictMode>
        <TrayWindow />
      </React.StrictMode>
    );
  } else {
    root.render(
      <React.StrictMode>
        <OverlayApp />
      </React.StrictMode>
    );
  }
}
