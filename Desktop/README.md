# DSM Music for Windows

A Windows 10/11 desktop edition of DSM Music. Import local audio files, search your collection, and play songs offline.

## Build locally
1. Install Node.js 22 or newer.
2. Open a terminal in this folder.
3. Run `npm install`.
4. Run `npm start` to launch the app.
5. Run `npm run dist:win` to create the Windows installer in `dist`.

Imported audio is copied into the app's Windows user-data folder so it remains available after closing or updating the app. This first Windows edition keeps its library locally on the PC; Google Drive sync with the iPhone edition is not connected yet.