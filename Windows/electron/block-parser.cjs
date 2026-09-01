const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const cache = new Map();

function inertValue() {
  const target = function () { return proxy; };
  const proxy = new Proxy(target, {
    get: (_target, key) => {
      if (key === Symbol.toPrimitive) return () => "";
      if (key === "then") return undefined;
      return proxy;
    },
    apply: () => proxy,
    construct: () => proxy
  });
  return proxy;
}

function evaluateBlock(filePath) {
  const stat = fs.statSync(filePath);
  const key = `${filePath}|${stat.mtimeMs}|${stat.size}`;
  const cached = cache.get(key);
  if (cached) return cached;

  const source = fs.readFileSync(filePath, "utf8");
  const module = { exports: {} };
  const inert = inertValue();
  const sandbox = {
    module,
    exports: module.exports,
    require: () => inert,
    console: { log() {}, warn() {}, error() {} },
    Buffer: { from: () => inert },
    process: { env: {} },
    setTimeout: () => 0,
    clearTimeout() {}
  };
  vm.createContext(sandbox, {
    codeGeneration: { strings: false, wasm: false }
  });
  new vm.Script(source, { filename: filePath }).runInContext(sandbox, { timeout: 150 });
  const exported = module.exports?.default || module.exports;
  if (!exported || typeof exported !== "object") {
    throw new Error(`${path.basename(filePath)} does not export a block object.`);
  }
  const result = { exported, source };
  cache.clear();
  cache.set(key, result);
  return result;
}

function resolveMetadata(value, optionValues) {
  if (typeof value !== "function") return value || [];
  try {
    return value({ options: optionValues || {} }) || [];
  } catch {
    return [];
  }
}

function normalizeTypes(types) {
  const values = Array.isArray(types) ? types : [];
  return values.length ? values.map((value) => String(value).toLowerCase()) : ["unspecified"];
}

function normalizePorts(values, direction) {
  if (!Array.isArray(values)) return [];
  return values.filter((port) => port && port.id != null).map((port) => ({
    id: String(port.id),
    name: String(port.name ?? port.id),
    description: String(port.description ?? ""),
    types: normalizeTypes(port.types),
    required: Boolean(port.required),
    direction,
    allowsMultipleConnections: Boolean(direction === "input" ? port.multiInput : port.multiOutput)
  }));
}

function flattenChoices(value, result = []) {
  if (Array.isArray(value)) {
    for (const entry of value) {
      if (!entry || typeof entry !== "object") continue;
      if (String(entry.type || "").toUpperCase() === "GROUP") {
        flattenChoices(entry.options, result);
      } else if (entry.id != null) {
        result.push([String(entry.id), String(entry.name ?? entry.id)]);
      }
    }
  } else if (value && typeof value === "object") {
    for (const [id, name] of Object.entries(value)) result.push([id, String(name)]);
  }
  return result;
}

function normalizeOptions(values) {
  if (!Array.isArray(values)) return [];
  return values.filter((option) => option && option.id != null).map((option) => {
    const entries = flattenChoices(option.options);
    return {
      id: String(option.id),
      name: String(option.name ?? option.id),
      description: String(option.description ?? ""),
      type: String(option.type || "UNKNOWN").toUpperCase(),
      choices: Object.fromEntries(entries),
      choiceOrder: entries.map(([id]) => id),
      defaultValue: option.default ?? null
    };
  });
}

function parseBlockFile(filePath, optionValues = {}) {
  const { exported } = evaluateBlock(filePath);
  if (!exported.name) throw new Error(`${path.basename(filePath)} has no display name.`);
  return {
    id: path.basename(filePath),
    name: String(exported.name),
    description: String(exported.description ?? ""),
    category: String(exported.category ?? "Uncategorized"),
    autoExecute: Boolean(exported.auto_execute),
    inputs: normalizePorts(resolveMetadata(exported.inputs, optionValues), "input"),
    options: normalizeOptions(resolveMetadata(exported.options, optionValues)),
    outputs: normalizePorts(resolveMetadata(exported.outputs, optionValues), "output"),
    sourceFile: path.basename(filePath),
    usesDynamicMetadata: [exported.inputs, exported.options, exported.outputs].some(
      (value) => typeof value === "function"
    )
  };
}

function parseDirectory(directoryPath) {
  if (!fs.existsSync(directoryPath)) return { definitions: [], failures: [] };
  const definitions = [];
  const failures = [];
  for (const entry of fs.readdirSync(directoryPath, { withFileTypes: true })) {
    if (!entry.isFile() || path.extname(entry.name).toLowerCase() !== ".js") continue;
    const filePath = path.join(directoryPath, entry.name);
    if (!fs.readFileSync(filePath, "utf8").trim()) continue;
    try {
      definitions.push(parseBlockFile(filePath));
    } catch (error) {
      failures.push({ file: entry.name, message: error.message });
    }
  }
  definitions.sort((a, b) =>
    a.category.localeCompare(b.category) || a.name.localeCompare(b.name));
  return { definitions, failures };
}

module.exports = { parseBlockFile, parseDirectory };
