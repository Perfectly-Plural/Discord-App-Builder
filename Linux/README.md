# Discord App Builder for Linux

The Linux edition uses the shared Electron editor in `../Windows` so Windows
and Linux always read and write the same projects, blocks, and
`data/workspaces.json` files.

## Build

Requires Node.js 24 or newer.

```sh
cd ../Windows
npm ci
npm run typecheck
npm test
npm run build:linux
```

Packages are written to `../Windows/dist/`:

- x64 AppImage
- ARM64 AppImage
- x64 Debian package
- ARM64 Debian package

Settings are stored in the standard Linux user configuration directory,
normally `~/.config/Discord App Builder/settings.json`.
