const { contextBridge, ipcRenderer, webUtils } = require("electron");

contextBridge.exposeInMainWorld("builderAPI", {
  chooseProjectParent: () => ipcRenderer.invoke("dialog:project-parent"),
  chooseProject: () => ipcRenderer.invoke("dialog:project"),
  chooseWorkspaceFile: () => ipcRenderer.invoke("dialog:workspace-file"),
  chooseBlocksFolder: () => ipcRenderer.invoke("dialog:blocks-folder"),
  createProject: (parent, name) => ipcRenderer.invoke("project:create", parent, name),
  openProject: (projectPath) => ipcRenderer.invoke("project:open", projectPath),
  saveProject: (payload) => ipcRenderer.invoke("project:save", payload),
  importWorkspaces: (projectPath, filePath) =>
    ipcRenderer.invoke("project:import-workspaces", projectPath, filePath),
  importBlocks: (projectPath, folderPath) =>
    ipcRenderer.invoke("project:import-blocks", projectPath, folderPath),
  renameBlockFile: (payload) => ipcRenderer.invoke("project:rename-block", payload),
  configuredBlock: (projectPath, sourceFile, optionValues) =>
    ipcRenderer.invoke("project:configured-block", projectPath, sourceFile, optionValues),
  updateRuntime: (projectPath) => ipcRenderer.invoke("project:update-runtime", projectPath),
  revealProject: (projectPath) => ipcRenderer.invoke("project:reveal", projectPath),
  getSettings: () => ipcRenderer.invoke("settings:get"),
  saveSettings: (settings) => ipcRenderer.invoke("settings:save", settings),
  pathForFile: (file) => webUtils.getPathForFile(file),
  onMenuCommand: (callback) => {
    const listener = (_event, command) => callback(command);
    ipcRenderer.on("menu:command", listener);
    return () => ipcRenderer.removeListener("menu:command", listener);
  },
  onSmokeProject: (callback) => {
    const listener = (_event, projectPath) => callback(projectPath);
    ipcRenderer.on("smoke:open-project", listener);
    return () => ipcRenderer.removeListener("smoke:open-project", listener);
  }
});
