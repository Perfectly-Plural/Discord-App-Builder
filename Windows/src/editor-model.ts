import type {
  BlockDefinition, BlockOption, BlockPort, ValueType,
  WorkflowBlock, WorkflowConnection, WorkflowDocument
} from "./types";

export const valueColors: Record<ValueType, string> = {
  object: "#168df0",
  action: "#2ecc71",
  text: "#d42ee7",
  number: "#ff8a26",
  list: "#f2d341",
  boolean: "#ef5da8",
  date: "#7767e8",
  null: "#8b8d93",
  undefined: "#8b8d93",
  unspecified: "#a4a7ae"
};

export function makeID(length = 10): string {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  return Array.from(bytes, (value) => alphabet[value % alphabet.length]).join("");
}

export function accepts(source: BlockPort, target: BlockPort): boolean {
  if (source.direction === target.direction) return false;
  if (source.types.includes("unspecified") || target.types.includes("unspecified")) return true;
  return source.types.some((type) => target.types.includes(type));
}

export function resolvedType(source?: BlockPort, target?: BlockPort): ValueType {
  const own = source?.types.filter((type) => type !== "unspecified") || [];
  const other = target?.types.filter((type) => type !== "unspecified") || [];
  return own.find((type) => other.includes(type)) || own[0] || other[0] || "unspecified";
}

export function defaultOptionValue(option: BlockOption): unknown {
  if (option.defaultValue !== null && option.defaultValue !== undefined) return option.defaultValue;
  if (option.type === "CHECKBOX") return false;
  if (option.type === "MULTISELECT") return [];
  if (option.type === "SELECT") return option.choiceOrder[0] || Object.keys(option.choices)[0] || "";
  if (option.type === "NUMBER") return 0;
  return "";
}

export function minimumBlockHeight(
  block: WorkflowBlock,
  connectionCounts: Record<string, number> = {}
): number {
  const rowCount = (ports: BlockPort[], direction: "input" | "output") => ports.reduce((total, port) => {
    if (!port.allowsMultipleConnections) return total + 1;
    const connected = connectionCounts[`${direction}:${port.id}`] || 0;
    const storedValue = direction === "input" ? block.inputWireValues[port.id] : undefined;
    const stored = Array.isArray(storedValue) ? storedValue.length : 0;
    return total + Math.max(connected, stored) + 1;
  }, 0);

  const inputRows = rowCount(block.definition.inputs, "input");
  const outputRows = rowCount(block.definition.outputs, "output");
  const portRows = Math.max(inputRows, outputRows);
  const portContentHeight = portRows > 0 ? portRows * 22 + (portRows - 1) * 7 : 0;

  const optionContentHeight = block.definition.options.reduce((height, option) => {
    const controlHeight = option.type === "TEXT" || option.type === "UNKNOWN"
      ? 48
      : option.type === "MULTISELECT" ? 58 : 29;
    return height + 22 + 3 + controlHeight;
  }, 0) + Math.max(0, block.definition.options.length - 1) * 8;

  // Header (39) + body top/bottom padding (11 + 26) + the tallest body column.
  return Math.max(140, 76 + Math.max(portContentHeight, optionContentHeight));
}

export function createBlock(
  definition: BlockDefinition,
  workspaceID: string,
  document: WorkflowDocument,
  position: { x: number; y: number }
): WorkflowBlock {
  const sequences = document.blocks.map((block) => {
    const prefix = `${workspaceID}:`;
    return block.runtimeBlockID?.startsWith(prefix)
      ? Number(block.runtimeBlockID.slice(prefix.length)) : -1;
  }).filter(Number.isFinite);
  const sequence = Math.max(-1, ...sequences) + 1;
  return {
    id: crypto.randomUUID(),
    runtimeBlockID: `${workspaceID}:${sequence}`,
    definition,
    position,
    optionValues: Object.fromEntries(definition.options.map((option) => [option.id, defaultOptionValue(option)])),
    inputWireValues: Object.fromEntries(definition.inputs.map((port) => [
      port.id, port.allowsMultipleConnections ? [] : makeID()
    ])),
    blockFileName: definition.sourceFile.replace(/\.js$/i, ""),
    color: "",
    zIndex: document.blocks.length,
    width: definition.options.length ? 500 : 300,
    height: 180,
    isLocked: false,
    isActive: true
  };
}

export function removeConnections(
  document: WorkflowDocument,
  predicate: (connection: WorkflowConnection) => boolean
): WorkflowDocument {
  const removed = document.connections.filter(predicate);
  const blocks = document.blocks.map((block) => ({
    ...block,
    inputWireValues: { ...block.inputWireValues }
  }));
  for (const connection of removed) {
    const target = blocks.find((block) => block.id === connection.toBlockID);
    if (!target) continue;
    const value = target.inputWireValues[connection.toPortID];
    if (Array.isArray(value)) {
      target.inputWireValues[connection.toPortID] = value.filter((item) => item !== connection.wireID);
    } else if (value === connection.wireID) {
      target.inputWireValues[connection.toPortID] = makeID();
    }
  }
  return {
    ...document,
    blocks,
    connections: document.connections.filter((connection) => !predicate(connection))
  };
}

export function connectBlocks(
  document: WorkflowDocument,
  fromBlockID: string,
  fromPortID: string,
  toBlockID: string,
  toPortID: string
): WorkflowDocument {
  const sourceBlock = document.blocks.find((block) => block.id === fromBlockID);
  const targetBlock = document.blocks.find((block) => block.id === toBlockID);
  const source = sourceBlock?.definition.outputs.find((port) => port.id === fromPortID);
  const target = targetBlock?.definition.inputs.find((port) => port.id === toPortID);
  if (!sourceBlock || !targetBlock || !source || !target || !accepts(source, target)) return document;

  let next = document;
  if (!target.allowsMultipleConnections) {
    next = removeConnections(next, (connection) =>
      connection.toBlockID === toBlockID && connection.toPortID === toPortID);
  }
  const duplicate = next.connections.some((connection) =>
    connection.fromBlockID === fromBlockID && connection.fromPortID === fromPortID &&
    connection.toBlockID === toBlockID && connection.toPortID === toPortID);
  if (duplicate) return next;

  const wireID = makeID();
  const blocks = next.blocks.map((block) => {
    if (block.id !== toBlockID) return block;
    const current = block.inputWireValues[toPortID];
    return {
      ...block,
      inputWireValues: {
        ...block.inputWireValues,
        [toPortID]: target.allowsMultipleConnections
          ? [...(Array.isArray(current) ? current : []), wireID]
          : wireID
      }
    };
  });
  return {
    ...next,
    blocks,
    connections: [...next.connections, {
      id: crypto.randomUUID(), wireID, fromBlockID, fromPortID, toBlockID, toPortID
    }]
  };
}

export function portFor(
  document: WorkflowDocument,
  blockID: string,
  portID: string,
  direction: "input" | "output"
): BlockPort | undefined {
  const block = document.blocks.find((item) => item.id === blockID);
  return (direction === "input" ? block?.definition.inputs : block?.definition.outputs)
    ?.find((port) => port.id === portID);
}
