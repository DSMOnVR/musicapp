const { contextBridge, ipcRenderer } = require("electron");
contextBridge.exposeInMainWorld("dsm", {
  getLibrary: () => ipcRenderer.invoke("library:get"),
  importMusic: () => ipcRenderer.invoke("library:import"),
  saveLibrary: library => ipcRenderer.invoke("library:save", library),
  removeTrack: id => ipcRenderer.invoke("library:remove", id),
  audioUrl: file => ipcRenderer.invoke("audio:url", file),
  revealFile: file => ipcRenderer.invoke("library:reveal", file)
});