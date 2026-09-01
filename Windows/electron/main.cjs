const { app, BrowserWindow, Menu, dialog, ipcMain, nativeTheme, shell } = require("electron");
const fs = require("node:fs");
const path = require("node:path");
const store = require("./project-store.cjs");

let mainWindow;

function rendererCommand(command) {
  mainWindow?.webContents.send("menu:command", command);
}

function appIconPath() {
  return app.isPackaged
    ? path.join(process.resourcesPath, "assets", "AppIcon.png")
    : path.join(__dirname, "../../Assets/AppIcon.png");
}

function createMenu() {
  const template = [
    {
      label: "File",
      submenu: [
        { label: "New Project", accelerator: "CommandOrControl+N", click: () => rendererCommand("new-project") },
        { label: "Open Project", accelerator: "CommandOrControl+O", click: () => rendererCommand("open-project") },
        { type: "separator" },
        { label: "Save", accelerator: "CommandOrControl+S", click: () => rendererCommand("save") },
        { label: "Import Workspaces", click: () => rendererCommand("import-workspaces") },
        { label: "Import Blocks", click: () => rendererCommand("import-blocks") },
        { type: "separator" },
        { role: "quit" }
      ]
    },
    {
      label: "Edit",
      submenu: [
        { label: "Undo", accelerator: "CommandOrControl+Z", click: () => rendererCommand("undo") },
        { label: "Redo", accelerator: "CommandOrControl+Shift+Z", click: () => rendererCommand("redo") },
        { type: "separator" },
        { role: "cut" },
        { role: "copy" },
        { role: "paste" },
        { label: "Delete Selection", accelerator: "Delete", click: () => rendererCommand("delete") },
        { role: "selectAll" }
      ]
    },
    {
      label: "View",
      submenu: [
        { role: "reload" },
        { role: "toggleDevTools" },
        { type: "separator" },
        { role: "resetZoom" },
        { role: "zoomIn" },
        { role: "zoomOut" },
        { role: "togglefullscreen" }
      ]
    }
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1500,
    height: 940,
    minWidth: 980,
    minHeight: 640,
    title: "Discord App Builder",
    backgroundColor: "#1e1f22",
    icon: appIconPath(),
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  });

  if (process.env.DAB_CAPTURE_PATH) {
    mainWindow.webContents.on("console-message", (event) => {
      console.log(`DAB_RENDERER_CONSOLE ${event.level} ${event.message}`);
    });
    mainWindow.webContents.on("render-process-gone", (_event, details) => {
      console.error(`DAB_RENDERER_GONE ${JSON.stringify(details)}`);
    });
  }

  if (process.env.VITE_DEV_SERVER_URL) {
    mainWindow.loadURL(process.env.VITE_DEV_SERVER_URL);
  } else if (!app.isPackaged) {
    mainWindow.loadURL("http://localhost:5173");
  } else {
    mainWindow.loadFile(path.join(__dirname, "../dist-renderer/index.html"));
  }

  if (process.env.DAB_SMOKE_PROJECT || process.env.DAB_CAPTURE_PATH) {
    mainWindow.webContents.once("did-finish-load", () => {
      if (process.env.DAB_SMOKE_PROJECT) {
        mainWindow.webContents.send("smoke:open-project", process.env.DAB_SMOKE_PROJECT);
      }
      if (process.env.DAB_CAPTURE_PATH) {
        setTimeout(async () => {
          const image = await mainWindow.webContents.capturePage();
          fs.writeFileSync(process.env.DAB_CAPTURE_PATH, image.toPNG());
          const metrics = await mainWindow.webContents.executeJavaScript(`({
            workspaces: document.querySelectorAll('.workspace-row').length,
            blocks: document.querySelectorAll('.workflow-block').length,
            edges: document.querySelectorAll('.react-flow__edge').length,
            handles: document.querySelectorAll('.react-flow__handle').length,
            edgePaths: document.querySelectorAll('.react-flow__edge-path').length,
            width: document.documentElement.scrollWidth,
            height: document.documentElement.scrollHeight
          })`);
          console.log(`DAB_SMOKE_METRICS ${JSON.stringify(metrics)}`);
          if (process.env.DAB_SMOKE_INTERACTIONS) {
            const interactionStart = await mainWindow.webContents.executeJavaScript(`(async () => {
              const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
              const edge = document.querySelector('.react-flow__edge');
              edge?.dispatchEvent(new MouseEvent('click', { bubbles: true, clientX: 700, clientY: 400 }));
              await delay(100);
              const select = document.querySelector('.option-control:is(select):not([multiple])');
              let selectChanged = false;
              if (select && select.options.length > 1) {
                select.value = select.options[select.selectedIndex === 0 ? 1 : 0].value;
                select.dispatchEvent(new Event('change', { bubbles: true }));
                selectChanged = true;
              }
              return {
                selectedEdge: Boolean(document.querySelector('.react-flow__edge.selected')),
                selectChanged,
                edgesBeforeDelete: document.querySelectorAll('.react-flow__edge').length
              };
            })()`);
            mainWindow.webContents.send("menu:command", "delete");
            await new Promise((resolve) => setTimeout(resolve, 300));
            const interactionEnd = await mainWindow.webContents.executeJavaScript(`(async () => {
              const pane = document.querySelector('.react-flow__pane');
              pane?.dispatchEvent(new MouseEvent('contextmenu', {
                bubbles: true, cancelable: true, clientX: 760, clientY: 440
              }));
              await new Promise(resolve => setTimeout(resolve, 100));
              return {
                edgesAfterDelete: document.querySelectorAll('.react-flow__edge').length,
                blockPicker: Boolean(document.querySelector('.block-picker'))
              };
            })()`);
            console.log(`DAB_SMOKE_INTERACTIONS ${JSON.stringify({
              ...interactionStart,
              ...interactionEnd
            })}`);
          }
        }, 5000);
      }
    });
  }
}

function settingsPath() {
  return path.join(app.getPath("userData"), "settings.json");
}

function readSettings() {
  try {
    return JSON.parse(fs.readFileSync(settingsPath(), "utf8"));
  } catch {
    return { appearance: "system", recentProjects: [] };
  }
}

function writeSettings(settings) {
  fs.mkdirSync(path.dirname(settingsPath()), { recursive: true });
  fs.writeFileSync(settingsPath(), JSON.stringify(settings, null, 2));
  nativeTheme.themeSource = settings.appearance || "system";
  return settings;
}

function registerHandlers() {
  ipcMain.handle("dialog:project-parent", async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      title: "Choose where to create the project",
      properties: ["openDirectory", "createDirectory"]
    });
    return result.canceled ? null : result.filePaths[0];
  });
  ipcMain.handle("dialog:project", async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      title: "Open Bot Project",
      properties: ["openDirectory"]
    });
    return result.canceled ? null : result.filePaths[0];
  });
  ipcMain.handle("dialog:workspace-file", async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      title: "Import workspaces.json",
      properties: ["openFile"],
      filters: [{ name: "Workspace JSON", extensions: ["json"] }]
    });
    return result.canceled ? null : result.filePaths[0];
  });
  ipcMain.handle("dialog:blocks-folder", async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      title: "Import Blocks Folder",
      properties: ["openDirectory"]
    });
    return result.canceled ? null : result.filePaths[0];
  });

  ipcMain.handle("project:create", (_event, parent, name) => store.createProject(parent, name));
  ipcMain.handle("project:open", (_event, projectPath) => store.openProject(projectPath));
  ipcMain.handle("project:save", (_event, payload) => store.saveProject(payload));
  ipcMain.handle("project:import-workspaces", (_event, projectPath, filePath) =>
    store.importWorkspaces(projectPath, filePath));
  ipcMain.handle("project:import-blocks", (_event, projectPath, folderPath) =>
    store.importBlocks(projectPath, folderPath));
  ipcMain.handle("project:rename-block", (_event, payload) => store.renameBlockFile(payload));
  ipcMain.handle("project:configured-block", (_event, projectPath, sourceFile, optionValues) =>
    store.configuredBlock(projectPath, sourceFile, optionValues));
  ipcMain.handle("project:update-runtime", (_event, projectPath) => store.updateRuntime(projectPath));
  ipcMain.handle("project:reveal", (_event, projectPath) => shell.showItemInFolder(projectPath));
  ipcMain.handle("settings:get", () => readSettings());
  ipcMain.handle("settings:save", (_event, settings) => writeSettings(settings));
}

app.whenReady().then(() => {
  if (process.platform === "win32") {
    app.setAppUserModelId("software.perfectlyplural.discord-app-builder");
  }
  const settings = readSettings();
  nativeTheme.themeSource = settings.appearance || "system";
  registerHandlers();
  createMenu();
  createWindow();
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => app.quit());
