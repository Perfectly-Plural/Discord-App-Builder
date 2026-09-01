# Discord App Builder for Windows and Linux

The Windows and Linux editions share a desktop package built with Electron and React.
It reads and writes the same bot project folders as the macOS edition, including
`data/workspaces.json`, project-local `blocks/*.js`, generated runtime files,
configuration, token, and log behavior.

## Develop

Requires Node.js 24 or newer.

```powershell
npm ci
npm run dev
```

Application settings are stored in the operating system's standard per-user
application data folder. On Windows this is the roaming application data folder;
on Linux it is normally `~/.config/Discord App Builder/settings.json`.

## Verify

```powershell
npm run typecheck
npm test
npm run build:renderer
```

## Build installers

```powershell
npm run build
```

The build creates x64 and ARM64 NSIS installers under `Windows/dist/`. Installing
the app adds Discord App Builder to the Start menu and can create a desktop icon.

Published GitHub releases build both Windows architectures and attach the
compiled `.exe` installers to the release.

## Build Linux packages

```sh
npm run build:linux
```

The Linux build creates x64 and ARM64 AppImages and Debian packages under
`Windows/dist/`. AppImages can run directly after being made executable; Debian
packages integrate the app with the desktop application menu.
