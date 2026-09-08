# Discord App Builder for Windows and Linux

The Windows and Linux editions share a desktop package built with Electron and React.
They read and write the shared Discord App Builder project format, including
`data/workspaces.json`, project-local `blocks/*.js`, generated runtime files,
configuration, token, and log behavior.

Project scaffolding templates live in the platform-neutral
`../Shared/project-templates.json` file.

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

Tagged GitHub releases provide portable Windows ZIPs for x64 and ARM64. The
NSIS commands remain available for local installer builds.

## Build Linux packages

```sh
npm run build:linux
```

The Linux build creates x64 and ARM64 AppImages, Debian packages, and Flatpak
bundles under `Windows/dist/`. AppImages can run directly after being made
executable; Debian and Flatpak packages integrate the app with the desktop
application menu. Flatpak packaging requires `flatpak` and `flatpak-builder`.

Pushing a `v*` tag runs the release workflow, which additionally builds RPM and
generic Linux ZIP packages and uploads those alongside the DEB, Flatpak, and
Windows ZIP artifacts.
