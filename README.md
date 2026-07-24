# Discord App Builder

A native macOS visual workflow editor for building Discord bots with
compatible block and workspace formats.

## Features

- Create a complete Discord bot project from the app.
- Open existing compatible bot project folders.
- Read and write the `data/workspaces.json` graph format.
- Drag a complete `workspaces.json` onto the app to import it.
- Import copied single-workspace JSON as a supported data format.
- Switch between recent projects from a Discord-style round project rail.
- Browse workspaces as Discord-style `#` channels inside collapsible categories.
- Open several project workspaces in tabs and switch between them without
  removing them from their categories.
- Create and rename categories and workspaces while preserving group metadata.
- Load compatible CommonJS blocks from a project's `blocks` folder.
- Show only blocks contained in the active project's `blocks` folder.
- Mirror all bot console output into numbered daily files in `log/`.
- Include workspace name, workspace ID, block ID, and block index in runtime
  block error messages.
- Import PAL or other compatible block folders into the active project.
- Right-click the canvas to search blocks by category and place one at the pointer.
- Drag empty canvas space with the left mouse button to pan each workspace.
- Edit block options directly on each block, move blocks, and drag between compatible ports to connect them.
- Support repeatable block connectors, retaining each existing wire and exposing
  another numbered connector for blocks that allow multiple inputs or outputs.
- Double-click a block title to rename its `.js` file and update that filename
  across every workspace in the project.
- Command-click blocks to select several, then copy and paste them with their
  settings and links between copied blocks.
- Select and delete individual links, or delete one or more selected blocks.
- Choose System, Light, or Dark appearance for the entire editor.
- Persist appearance and recent projects in
  `~/Library/Application Support/Discord App Builder/settings.json`.
- Work with all workspace groups and workspaces in an imported bot.
- Run generated projects with the included compatible Node.js runtime.
- Update an existing project's `bot.js` from the newest runtime bundled with
  the application while keeping a backup of the previous file.

The importer and workspace graph have been tested against the
`Perfectly-Plural/PAL` project: 594 JavaScript files and a workspace file with
6 groups, 17 workspaces, and 442 placed blocks.

## Generated Project

New projects contain:

```text
My Discord Bot/
├── blocks/
│   ├── bot_initialization_event.js
│   ├── console_log.js
│   └── text.js
├── data/
│   ├── data.json
│   ├── config.json
│   ├── INTENTS.txt
│   ├── token.txt
│   └── workspaces.json
├── bot.js
├── logger.js
├── sharding.js
├── token.js
└── package.json
```

The generated `package.json` includes the dependencies requested for this
project, including Discord.js 14, Eris, MySQL2, Express, Axios, and the
required utility packages.

Every bot launch creates a log such as `log/2026-07-24_1.log`. The final
number is the bot's run count for that local calendar day. Sharded launches
share one file across the shard manager and its bot processes.

To run a generated bot:

```sh
cd "/path/to/My Discord Bot"
npm install
```

Put only the plain Discord bot token in `data/token.txt` (no JSON, quotes, or
property name), then run:

```sh
npm start
```

`data/config.json` contains the application name and version, default command
prefix, server-specific prefixes, and bot owner IDs. The runtime prints the
configured name and version whenever the bot starts. Blocks can read it through `this.Config`,
`this.getConfig("commands.defaultPrefix")`, or the runtime object passed as
the second argument to their `code` function. Call `this.saveConfig()` after
changing configuration from a block.

For sharding:

```sh
npm run start:sharded
```

## Run the Editor

```sh
swift run DiscordAppBuilder
```

## Build a Double-Clickable Mac App

```sh
Scripts/package-app.sh
```

The packaging script uses the active Xcode installation when available, even if
`xcode-select` still points at the standalone Command Line Tools.

The clickable app is created at:

```text
dist/Discord App Builder.app
```

Published GitHub releases automatically build and attach
`Discord-App-Builder-macOS.zip`. That archive contains only the compiled
`Discord App Builder.app` bundle.

## Test

```sh
swift test
```

When `/private/tmp/pal-blocks-reference` exists, the suite also validates the
real PAL block library and workspace graph.
