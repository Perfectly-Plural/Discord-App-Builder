import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createRequire } from "node:module";
import { afterEach, describe, expect, test } from "vitest";

const require = createRequire(import.meta.url);
const {
  createProject, decodeGroups, documentForWorkspace, storedBlocksForDocument
} = require("../electron/project-store.cjs");
const { parseBlockFile } = require("../electron/block-parser.cjs");

const temporaryDirectories = [];

function temporaryDirectory() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "discord-app-builder-windows-"));
  temporaryDirectories.push(directory);
  return directory;
}

afterEach(() => {
  for (const directory of temporaryDirectories.splice(0)) {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

describe("Windows project compatibility", () => {
  test("accepts grouped, flat, and single workspace files", () => {
    const workspace = {
      id: "workspace", active: true,
      info: { title: "Main", description: "", thumbnail: "" },
      blocks: [], notes: []
    };
    expect(decodeGroups(workspace)[0].workspaces).toHaveLength(1);
    expect(decodeGroups([workspace])[0].info.title).toBe("Imported Workspaces");
    expect(decodeGroups([{
      id: "group", info: { title: "Category", collapsed: false }, workspaces: [workspace]
    }])[0].id).toBe("group");
  });

  test("round-trips connections through input and output wire IDs", () => {
    const definition = {
      id: "test.js", name: "Test", description: "", category: "Tests",
      autoExecute: false, options: [], sourceFile: "test.js", usesDynamicMetadata: false,
      inputs: [{
        id: "input", name: "Input", description: "", types: ["text"], required: false,
        direction: "input", allowsMultipleConnections: false
      }],
      outputs: [{
        id: "output", name: "Output", description: "", types: ["text"], required: false,
        direction: "output", allowsMultipleConnections: false
      }]
    };
    const workspace = {
      id: "workspace", active: true,
      info: { title: "Connections", description: "", thumbnail: "" }, notes: [],
      blocks: [
        { block_id: "workspace:0", color: "", x: 10, y: 20, z: 0, width: 300, height: 160, lock: false, name: "test", inputs: {}, options: {}, outputs: { output: ["wire"] }, active: true },
        { block_id: "workspace:1", color: "", x: 400, y: 20, z: 1, width: 300, height: 160, lock: false, name: "test", inputs: { input: "wire" }, options: {}, outputs: {}, active: true }
      ]
    };
    const document = documentForWorkspace(temporaryDirectory(), workspace, [definition]);
    expect(document.connections).toHaveLength(1);
    expect(document.connections[0].wireID).toBe("wire");
    const stored = storedBlocksForDocument(document);
    expect(stored[0].outputs.output).toEqual(["wire"]);
    expect(stored[1].inputs.input).toBe("wire");
  });

  test("creates the complete bot project scaffold", () => {
    const root = temporaryDirectory();
    const project = createProject(root, "Windows Bot");
    const expected = [
      "bot.js", "sharding.js", "logger.js", "token.js", "package.json",
      "data/workspaces.json", "data/config.json", "data/token.txt",
      "config/server.txt", "config/log.txt", "blocks/text.js"
    ];
    for (const relativePath of expected) {
      expect(fs.existsSync(path.join(project.projectPath, relativePath)), relativePath).toBe(true);
    }
    const packageJSON = JSON.parse(fs.readFileSync(path.join(project.projectPath, "package.json"), "utf8"));
    expect(packageJSON.dependencies["discord.js"]).toBe("^14.14.1");
    expect(packageJSON.dependencies.axios).toBe("^1.18.0");
    const config = JSON.parse(fs.readFileSync(path.join(project.projectPath, "data/config.json"), "utf8"));
    expect(config.application.name).toBe("Windows Bot");
  });

  test("evaluates dynamic metadata using saved options", () => {
    const directory = temporaryDirectory();
    const file = path.join(directory, "dynamic.js");
    fs.writeFileSync(file, `module.exports = {
      name: "Dynamic",
      category: "Tests",
      inputs(data) { return [{ id: data.options.kind || "value", types: [data.options.type || "text"], multiInput: true }]; },
      options: [{ id: "kind", type: "TEXT" }],
      outputs(data) { return [{ id: "result", types: [data.options.type || "text"], multiOutput: true }]; }
    }`);
    const block = parseBlockFile(file, { kind: "payload", type: "object" });
    expect(block.inputs[0].id).toBe("payload");
    expect(block.inputs[0].allowsMultipleConnections).toBe(true);
    expect(block.outputs[0].types).toEqual(["object"]);
    expect(block.outputs[0].allowsMultipleConnections).toBe(true);
  });
});
