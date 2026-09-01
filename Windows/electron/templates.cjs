const fs = require("node:fs");
const path = require("node:path");

function packagedTemplates() {
  const electronApp = process.versions.electron ? require("electron").app : null;
  if (electronApp?.isPackaged) {
    return JSON.parse(fs.readFileSync(
      path.join(process.resourcesPath, "templates", "templates.json"),
      "utf8"
    ));
  }
  return null;
}

function rawTemplate(name) {
  const packaged = packagedTemplates();
  if (packaged) {
    if (typeof packaged[name] !== "string") throw new Error(`Bundled template ${name} is missing.`);
    return packaged[name];
  }
  const source = fs.readFileSync(
    path.join(__dirname, "..", "..", "Sources", "DiscordAppBuilder", "ProjectTemplates.swift"),
    "utf8"
  );
  const marker = `static let ${name} = #\"\"\"`;
  const start = source.indexOf(marker);
  if (start < 0) throw new Error(`Bundled template ${name} is missing.`);
  const contentStart = source.indexOf("\n", start) + 1;
  const end = source.indexOf('\n    \"\"\"#', contentStart);
  if (end < 0) throw new Error(`Bundled template ${name} is incomplete.`);
  return source.slice(contentStart, end).replace(/^    /gm, "");
}

function configJSON(applicationName, applicationVersion = "1.0.0") {
  return JSON.stringify({
    application: { name: applicationName, version: applicationVersion },
    commands: { defaultPrefix: "!", serverPrefixes: {} },
    owners: []
  }, null, 2) + "\n";
}

function scaffoldFiles(applicationName) {
  return {
    "package.json": rawTemplate("packageJSON"),
    "bot.js": rawTemplate("botRuntime"),
    "sharding.js": rawTemplate("sharding"),
    "logger.js": rawTemplate("logger"),
    "token.js": rawTemplate("tokenReader"),
    "data/data.json": rawTemplate("dataJSON"),
    "data/config.json": configJSON(applicationName),
    "data/token.txt": "",
    "data/INTENTS.txt": rawTemplate("intents"),
    "config/server.txt": "",
    "config/log.txt": "",
    "blocks/bot_initialization_event.js": rawTemplate("initializationBlock"),
    "blocks/text.js": rawTemplate("textBlock"),
    "blocks/console_log.js": rawTemplate("consoleLogBlock")
  };
}

module.exports = { configJSON, rawTemplate, scaffoldFiles };
