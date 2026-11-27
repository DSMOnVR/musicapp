const { app, BrowserWindow, ipcMain, dialog } = require("electron");
const fs = require("fs");
const path = require("path");
const { pathToFileURL } = require("url");
const crypto = require("crypto");

let win;
const dataDir = () => path.join(app.getPath("userData"), "library");
const musicDir = () => path.join(dataDir(), "music");
const dbFile = () => path.join(dataDir(), "library.json");
function readLibrary() {
  try { return JSON.parse(fs.readFileSync(dbFile(), "utf8")); }
  catch { return { tracks: [], playlists: [] }; }
}
function saveLibrary(data) {
  fs.mkdirSync(dataDir(), { recursive: true });
  fs.writeFileSync(dbFile(), JSON.stringify(data, null, 2));
}
function createWindow() {
  win = new BrowserWindow({
    width: 1440, height: 900, minWidth: 900, minHeight: 620,
    backgroundColor: "#101114",
    title: "DSM Music",
    webPreferences: { preload: path.join(__dirname, "preload.js"), contextIsolation: true, nodeIntegration: false }
  });
  win.loadFile("index.html");
}
app.whenReady().then(() => {
  fs.mkdirSync(musicDir(), { recursive: true });
  createWindow();
  app.on("activate", () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});
app.on("window-all-closed", () => { if (process.platform !== "darwin") app.quit(); });

ipcMain.handle("library:get", () => readLibrary());
ipcMain.handle("library:import", async () => {
  const result = await dialog.showOpenDialog(win, {
    title: "Import music",
    properties: ["openFile", "multiSelections"],
    filters: [{ name: "Audio", extensions: ["mp3","m4a","aac","wav","flac","ogg","aiff","aif","mp4"] }]
  });
  if (result.canceled) return readLibrary();
  const library = readLibrary();
  for (const source of result.filePaths) {
    const ext = path.extname(source).toLowerCase() || ".audio";
    const id = crypto.randomUUID();
    const destination = path.join(musicDir(), id + ext);
    fs.copyFileSync(source, destination);
    const base = path.basename(source, ext);
    const parts = base.split(" - ");
    library.tracks.push({ id, title: parts.length > 1 ? parts.slice(1).join(" - ") : base, artist: parts.length > 1 ? parts[0] : "Unknown Artist", album: "Unknown Album", file: destination, addedAt: Date.now() });
  }
  saveLibrary(library);
  return library;
});
ipcMain.handle("library:save", (_event, library) => { saveLibrary(library); return true; });
ipcMain.handle("library:remove", (_event, id) => {
  const library = readLibrary();
  const track = library.tracks.find(t => t.id === id);
  if (track) { try { fs.unlinkSync(track.file); } catch {} }
  library.tracks = library.tracks.filter(t => t.id !== id);
  library.playlists = (library.playlists || []).map(p => ({ ...p, trackIds: (p.trackIds || []).filter(x => x !== id) }));
  saveLibrary(library);
  return library;
});
ipcMain.handle("audio:url", (_event, file) => pathToFileURL(file).href);
ipcMain.handle("library:reveal", (_event, file) => require("electron").shell.showItemInFolder(file));
