const fs = require("node:fs");
const path = require("node:path");

const root = path.join(__dirname, "..", "..");
const source = fs.readFileSync(
  path.join(root, "Sources", "DiscordAppBuilder", "ProjectTemplates.swift"),
  "utf8"
);
const names = [
  "packageJSON", "botRuntime", "sharding", "logger", "tokenReader", "dataJSON",
  "intents", "initializationBlock", "textBlock", "consoleLogBlock"
];

function extract(name) {
  const marker = `static let ${name} = #\"\"\"`;
  const start = source.indexOf(marker);
  if (start < 0) throw new Error(`Template ${name} is missing.`);
  const contentStart = source.indexOf("\n", start) + 1;
  const end = source.indexOf('\n    \"\"\"#', contentStart);
  if (end < 0) throw new Error(`Template ${name} is incomplete.`);
  return source.slice(contentStart, end).replace(/^    /gm, "");
}

const templates = Object.fromEntries(names.map((name) => [name, extract(name)]));
const destination = path.join(__dirname, "..", "generated", "templates.json");
fs.mkdirSync(path.dirname(destination), { recursive: true });
fs.writeFileSync(destination, `${JSON.stringify(templates)}\n`);
console.log(`Generated ${destination}`);
