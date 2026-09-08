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

function sharedTemplates() {
  return JSON.parse(fs.readFileSync(
    path.join(__dirname, "..", "..", "Shared", "project-templates.json"),
    "utf8"
  ));
}

function rawTemplate(name) {
  const templates = packagedTemplates() || sharedTemplates();
  if (typeof templates[name] !== "string") throw new Error(`Bundled template ${name} is missing.`);
  return templates[name];
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
