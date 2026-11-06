// Exposes a tiny, safe API to the game page.
// The game checks window.kitchenRat.desktop to switch to the full-window layout.
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('kitchenRat', {
  desktop: true,
  quit: () => ipcRenderer.send('quit'),
});
