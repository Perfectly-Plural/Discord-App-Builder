const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { parseBlockFile, parseDirectory } = require("./block-parser.cjs");
const { rawTemplate, scaffoldFiles } = require("./templates.cjs");

const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

function makeID(length = 10) {
  let result = "";
  for (let index = 0; index < length; index += 1) {
    result += alphabet[crypto.randomInt(alphabet.length)];
  }
  return result;
}

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJSON(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const temporary = `${filePath}.tmp`;
  fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`);
  fs.renameSync(temporary, filePath);
}

function normalizeWorkspace(workspace) {
  return {
    id: String(workspace.id || makeID()),
    active: workspace.active !== false,
    info: {
      title: String(workspace.info?.title || "Untitled Workspace"),
      description: String(workspace.info?.description || ""),
      thumbnail: String(workspace.info?.thumbnail || "")
    },
    blocks: Array.isArray(workspace.blocks) ? workspace.blocks : [],
    notes: Array.isArray(workspace.notes) ? workspace.notes : []
  };
}

function decodeGroups(data) {
  if (!Array.isArray(data)) data = [data];
  if (data.every((item) => Array.isArray(item?.workspaces))) {
    return data.map((group) => ({
      id: String(group.id || makeID()),
      info: {
        title: String(group.info?.title || "Workspaces"),
        collapsed: Boolean(group.info?.collapsed)
      },
      workspaces: group.workspaces.map(normalizeWorkspace)
    }));
  }
  if (data.every((item) => Array.isArray(item?.blocks))) {
    return [{
      id: makeID(),
      info: { title: "Imported Workspaces", collapsed: false },
      workspaces: data.map(normalizeWorkspace)
    }];
  }
  throw new Error("The workspace JSON is not in a supported format.");
}

function wireIDs(value) {
  if (typeof value === "string") return value ? [value] : [];
  if (Array.isArray(value)) return value.filter((item) => typeof item === "string" && item);
  return [];
}

function missingDefinition(stored) {
  const port = (id, direction) => ({
    id,
    name: id,
    description: `Imported ${direction}`,
    types: ["unspecified"],
    required: false,
    direction,
    allowsMultipleConnections: false
  });
  return {
    id: `${stored.name}.js`,
    name: stored.name,
    description: "The block file is not available in this project's blocks folder.",
    category: "Missing Blocks",
    autoExecute: false,
    inputs: Object.keys(stored.inputs || {}).sort().map((id) => port(id, "input")),
    options: Object.keys(stored.options || {}).sort().map((id) => ({
      id, name: id, description: "Imported option", type: "TEXT", choices: {}, choiceOrder: []
    })),
    outputs: Object.keys(stored.outputs || {}).sort().map((id) => port(id, "output")),
    sourceFile: `${stored.name}.js`,
    usesDynamicMetadata: false
  };
}

function minimumBlockSize(definition) {
  const connectorColumns = Number(definition.inputs.length > 0) + Number(definition.outputs.length > 0);
  const width = definition.options.length ? 300 + connectorColumns * 90 : 220;
  const inputRows = definition.inputs.length;
  const outputRows = definition.outputs.length;
  const portHeight = Math.max(inputRows, outputRows, 1) * 32;
  const optionHeight = definition.options.reduce((height, option) =>
    height + 20 + (["TEXT", "UNKNOWN"].includes(option.type) ? 48 : 26), 0)
    + Math.max(0, definition.options.length - 1) * 9;
  return { width, height: Math.max(140, 78 + Math.max(portHeight, optionHeight)) };
}

function documentForWorkspace(projectPath, workspace, library) {
  const definitions = new Map(library.map((item) => [path.parse(item.sourceFile).name, item]));
  const blocks = workspace.blocks.map((stored, index) => {
    let definition = definitions.get(stored.name) || missingDefinition(stored);
    if (definition.usesDynamicMetadata) {
      try {
        definition = parseBlockFile(path.join(projectPath, "blocks", definition.sourceFile), stored.options || {});
      } catch {}
    }
    const minimum = minimumBlockSize(definition);
    return {
      id: crypto.randomUUID(),
      runtimeBlockID: stored.block_id || stored.id || `${workspace.id}:${index}`,
      definition,
      position: { x: Number(stored.x || 0), y: Number(stored.y || 0) },
      optionValues: stored.options || {},
      inputWireValues: stored.inputs || {},
      blockFileName: stored.name,
      color: stored.color || "",
      zIndex: Number(stored.z || 0),
      width: Math.max(minimum.width, Number(stored.width || 300)),
      height: Math.max(minimum.height, Number(stored.height || 160)),
      isLocked: Boolean(stored.lock),
      isActive: stored.active !== false
    };
  });

  const outputSources = new Map();
  blocks.forEach((block, index) => {
    for (const [portID, value] of Object.entries(workspace.blocks[index].outputs || {})) {
      for (const wireID of wireIDs(value)) outputSources.set(wireID, { blockID: block.id, portID });
    }
  });
  const connections = [];
  for (const block of blocks) {
    for (const [portID, value] of Object.entries(block.inputWireValues)) {
      for (const wireID of wireIDs(value)) {
        const source = outputSources.get(wireID);
        if (!source) continue;
        connections.push({
          id: crypto.randomUUID(), wireID,
          fromBlockID: source.blockID, fromPortID: source.portID,
          toBlockID: block.id, toPortID: portID
        });
      }
    }
  }
  return { name: workspace.info.title, blocks, connections };
}

function storedBlocksForDocument(document) {
  const stored = document.blocks.map((block) => ({
    block_id: block.runtimeBlockID || null,
    color: block.color || "",
    x: block.position.x,
    y: block.position.y,
    z: block.zIndex || 0,
    width: block.width,
    height: block.height,
    lock: Boolean(block.isLocked),
    name: block.blockFileName,
    inputs: block.inputWireValues || {},
    options: block.optionValues || {},
    outputs: Object.fromEntries(block.definition.outputs.map((port) => [port.id, []])),
    active: block.isActive !== false
  }));
  const indexes = new Map(document.blocks.map((block, index) => [block.id, index]));
  for (const connection of document.connections) {
    const index = indexes.get(connection.fromBlockID);
    if (index == null) continue;
    const wires = stored[index].outputs[connection.fromPortID] || [];
    if (!wires.includes(connection.wireID)) wires.push(connection.wireID);
    stored[index].outputs[connection.fromPortID] = wires;
  }
  return stored;
}

function openProject(projectPath) {
  const root = path.resolve(projectPath);
  const workspacePath = path.join(root, "data", "workspaces.json");
  if (!fs.existsSync(workspacePath)) throw new Error("No data/workspaces.json file was found.");
  const groups = decodeGroups(readJSON(workspacePath));
  const parsed = parseDirectory(path.join(root, "blocks"));
  const documents = {};
  for (const group of groups) {
    for (const workspace of group.workspaces) {
      documents[workspace.id] = documentForWorkspace(root, workspace, parsed.definitions);
    }
  }
  return {
    projectPath: root,
    projectName: path.basename(root),
    groups,
    documents,
    library: parsed.definitions,
    parserFailures: parsed.failures
  };
}

function createProject(parentPath, name) {
  const cleanName = String(name || "").trim();
  if (!cleanName || /[<>:\"/\\|?*]/.test(cleanName)) throw new Error("Choose a valid project name.");
  const projectPath = path.join(path.resolve(parentPath), cleanName);
  if (fs.existsSync(projectPath) && fs.readdirSync(projectPath).length) {
    throw new Error("That project folder already exists and is not empty.");
  }
  for (const directory of ["blocks", "data", "config"]) {
    fs.mkdirSync(path.join(projectPath, directory), { recursive: true });
  }
  const workspace = normalizeWorkspace({
    id: makeID(), active: true,
    info: { title: "Main Workspace", description: "", thumbnail: "" },
    blocks: [], notes: []
  });
  const groups = [{
    id: makeID(), info: { title: "Workspaces", collapsed: false }, workspaces: [workspace]
  }];
  for (const [relativePath, contents] of Object.entries(scaffoldFiles(cleanName))) {
    const destination = path.join(projectPath, relativePath);
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    fs.writeFileSync(destination, contents);
  }
  writeJSON(path.join(projectPath, "data", "workspaces.json"), groups);
  return openProject(projectPath);
}

function saveProject(payload) {
  const groups = structuredClone(payload.groups);
  for (const group of groups) {
    for (const workspace of group.workspaces) {
      const document = payload.documents[workspace.id];
      if (!document) continue;
      workspace.info.title = document.name;
      workspace.blocks = storedBlocksForDocument(document);
    }
  }
  writeJSON(path.join(payload.projectPath, "data", "workspaces.json"), groups);
  return { groups };
}

function importWorkspaces(projectPath, filePath) {
  const groups = decodeGroups(readJSON(filePath));
  writeJSON(path.join(projectPath, "data", "workspaces.json"), groups);
  return openProject(projectPath);
}

function collectJavaScriptFiles(directoryPath, result = []) {
  for (const entry of fs.readdirSync(directoryPath, { withFileTypes: true })) {
    const item = path.join(directoryPath, entry.name);
    if (entry.isDirectory()) collectJavaScriptFiles(item, result);
    else if (entry.isFile() && path.extname(entry.name).toLowerCase() === ".js") result.push(item);
  }
  return result;
}

function importBlocks(projectPath, folderPath) {
  const destination = path.join(projectPath, "blocks");
  fs.mkdirSync(destination, { recursive: true });
  const files = collectJavaScriptFiles(folderPath);
  for (const file of files) fs.copyFileSync(file, path.join(destination, path.basename(file)));
  return openProject(projectPath);
}

function normalizeBlockName(value) {
  const clean = String(value || "").trim().replace(/\.js$/i, "");
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(clean)) {
    throw new Error("Use only letters, numbers, underscores, or hyphens.");
  }
  return clean;
}

function renameBlockFile({ projectPath, oldName, newName, groups, documents }) {
  const clean = normalizeBlockName(newName);
  const source = path.join(projectPath, "blocks", `${oldName}.js`);
  const destination = path.join(projectPath, "blocks", `${clean}.js`);
  if (!fs.existsSync(source)) throw new Error(`${oldName}.js could not be found.`);
  if (source !== destination && fs.existsSync(destination)) throw new Error(`${clean}.js already exists.`);
  fs.renameSync(source, destination);
  for (const group of groups) {
    for (const workspace of group.workspaces) {
      for (const block of workspace.blocks) if (block.name === oldName) block.name = clean;
      const document = documents[workspace.id];
      if (!document) continue;
      for (const block of document.blocks) if (block.blockFileName === oldName) block.blockFileName = clean;
    }
  }
  saveProject({ projectPath, groups, documents });
  return openProject(projectPath);
}

function updateRuntime(projectPath) {
  const botPath = path.join(projectPath, "bot.js");
  let backupPath = null;
  if (fs.existsSync(botPath)) {
    const backups = path.join(projectPath, "backups");
    fs.mkdirSync(backups, { recursive: true });
    const stamp = new Date().toISOString().replace(/[:.]/g, "-");
    backupPath = path.join(backups, `bot-${stamp}.js`);
    fs.copyFileSync(botPath, backupPath);
  }
  fs.writeFileSync(botPath, rawTemplate("botRuntime"));
  return { backupPath };
}

function configuredBlock(projectPath, sourceFile, optionValues) {
  return parseBlockFile(path.join(projectPath, "blocks", path.basename(sourceFile)), optionValues);
}

module.exports = {
  configuredBlock, createProject, decodeGroups, documentForWorkspace, importBlocks, importWorkspaces,
  makeID, openProject, renameBlockFile, saveProject, storedBlocksForDocument, updateRuntime
};
