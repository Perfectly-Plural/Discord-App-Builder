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
- x64 Flatpak bundle
- ARM64 Flatpak bundle

Building Flatpak bundles additionally requires `flatpak` and `flatpak-builder`.
The bundles use the Freedesktop 25.08 runtime and can be installed with:

```sh
flatpak install --user ./Discord-App-Builder-Linux-x86_64-0.2.0.flatpak
```

Pushing a `v*` tag creates a GitHub Release containing x64 and ARM64 DEB, RPM,
Flatpak, generic Linux ZIP, and Windows ZIP packages. The version embedded in
the packages is derived from the tag.

Settings are stored in the standard Linux user configuration directory,
normally `~/.config/Discord App Builder/settings.json`.
