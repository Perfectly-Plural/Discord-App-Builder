# Discord App Builder

## What does it do?

Discord App Builder is a visual workflow editor for creating Discord bots on
Windows and Linux. It lets you build bot behavior by placing blocks, editing
their options, and connecting them together.

You can create new bot projects, open compatible existing projects, organize
workflows, import additional blocks, and run the generated bot from the app.

## How to build

Install Node.js 24 or newer, then install the project dependencies:

```sh
cd Windows
npm ci
```

Build Windows installers:

```sh
npm run build
```

Build Linux AppImage, DEB, and Flatpak packages:

```sh
npm run build:linux
```

Linux Flatpak builds also require `flatpak` and `flatpak-builder`. Build output
is written to `Windows/dist/`.

Pushing a version tag such as `v0.2.0` runs the release workflow, which creates
the Linux DEB, RPM, Flatpak and ZIP packages and the Windows ZIP packages.

## How to use

1. Launch Discord App Builder and choose **New Project** or **Open Project**.
2. Create or select a workspace.
3. Right-click the canvas to add blocks, configure them, and connect their
   input and output ports.
4. Save the project and place your Discord bot token in `data/token.txt`.
5. Run the bot from Discord App Builder, or run it from a terminal:

```sh
cd "/path/to/your/bot"
npm install
npm start
```
