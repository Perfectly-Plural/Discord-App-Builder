import { describe, expect, test } from "vitest";
import { connectBlocks, removeConnections } from "./editor-model";
import type { BlockDefinition, WorkflowDocument } from "./types";

const definition: BlockDefinition = {
  id: "test.js", name: "Test", description: "", category: "Tests",
  autoExecute: false, options: [], sourceFile: "test.js", usesDynamicMetadata: false,
  inputs: [{ id: "input", name: "Input", description: "", types: ["text"], required: false, direction: "input", allowsMultipleConnections: false }],
  outputs: [{ id: "output", name: "Output", description: "", types: ["text"], required: false, direction: "output", allowsMultipleConnections: false }]
};

function document(): WorkflowDocument {
  return {
    name: "Test",
    blocks: ["source", "target"].map((id, index) => ({
      id, runtimeBlockID: `workspace:${index}`, definition, position: { x: index * 300, y: 0 },
      optionValues: {}, inputWireValues: { input: `empty-${index}` }, blockFileName: "test",
      color: "", zIndex: index, width: 300, height: 160, isLocked: false, isActive: true
    })),
    connections: []
  };
}

describe("workflow editing", () => {
  test("connects compatible ports and removes only the selected link", () => {
    const connected = connectBlocks(document(), "source", "output", "target", "input");
    expect(connected.connections).toHaveLength(1);
    expect(connected.blocks).toHaveLength(2);
    const wireID = connected.connections[0].wireID;
    expect(connected.blocks[1].inputWireValues.input).toBe(wireID);

    const removed = removeConnections(connected, (connection) => connection.id === connected.connections[0].id);
    expect(removed.connections).toHaveLength(0);
    expect(removed.blocks).toHaveLength(2);
    expect(removed.blocks[1].inputWireValues.input).not.toBe(wireID);
  });

  test("rejects incompatible value types", () => {
    const incompatible = structuredClone(definition);
    incompatible.inputs[0].types = ["number"];
    const current = document();
    current.blocks[1].definition = incompatible;
    expect(connectBlocks(current, "source", "output", "target", "input").connections).toHaveLength(0);
  });
});
