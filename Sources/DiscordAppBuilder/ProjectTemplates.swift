import Foundation

enum ProjectTemplates {
    static let packageJSON = #"""
    {
      "name": "discord-app-builder-bot",
      "author": "Discord App Builder",
      "description": "Discord Bot created with Discord App Builder.",
      "version": "1.0.0",
      "main": "bot.js",
      "scripts": {
        "start": "node bot.js",
        "start:sharded": "node sharding.js"
      },
      "dependencies": {
        "discord.js": "^14.14.1",
        "eris": "^0.17.2",
        "fstorm": "^0.1.3",
        "mysql2": "^3.9.1",
        "node-cron": "^3.0.3",
        "resolve-dependencies": "^6.0.9",
        "semver": "^7.6.0",
        "node-fetch": "^3.3.2",
        "express": "^4.19.2",
        "discord-html-transcripts": "^3.2.0",
        "discord-banner": "^1.6.7",
        "esm": "^3.2.25",
        "discord-badges": "^0.0.0",
        "axios": "^1.18.0"
      }
    }

    """#

    static let sharding = #"""
    'use strict'

    const path = require('path')
    process.chdir(__dirname)

    const { installConsoleLogger } = require('./logger')
    installConsoleLogger()

    const { ShardingManager } = require('discord.js')
    const { readBotToken } = require('./token')

    async function startShards() {
      const token = readBotToken()
      const manager = new ShardingManager(path.join(__dirname, 'bot.js'), { token })
      await manager.spawn()
    }

    startShards().catch(error => {
      console.error('[Discord App Builder] Sharded bot failed to start:', error.message)
      process.exitCode = 1
    })

    """#

    static let tokenReader = #"""
    'use strict'

    const fs = require('fs')
    const path = require('path')

    const tokenPath = path.join(__dirname, 'data', 'token.txt')

    function readBotToken() {
      let contents
      try {
        contents = fs.readFileSync(tokenPath, 'utf8')
      } catch (error) {
        if (error.code === 'ENOENT') {
          throw new Error('Bot token file is missing. Create data/token.txt and paste the Discord bot token into it.')
        }
        throw new Error(`Could not read data/token.txt: ${error.message}`)
      }

      const token = contents.trim()
      if (!token) {
        throw new Error('data/token.txt is empty. Paste the Discord bot token into the file as plain text.')
      }
      if (/\s/.test(token)) {
        throw new Error('data/token.txt contains whitespace inside the token. It must contain only the plain Discord bot token.')
      }
      return token
    }

    module.exports = {
      readBotToken,
      tokenPath
    }

    """#

    static let logger = #"""
    'use strict'

    const fs = require('fs')
    const path = require('path')

    const loggerStateKey = Symbol.for('discord-app-builder.console-logger')

    function localDateKey(date = new Date()) {
      const year = String(date.getFullYear()).padStart(4, '0')
      const month = String(date.getMonth() + 1).padStart(2, '0')
      const day = String(date.getDate()).padStart(2, '0')
      return `${year}-${month}-${day}`
    }

    function reserveRunFile(logDirectory) {
      fs.mkdirSync(logDirectory, { recursive: true })
      const date = localDateKey()
      let run = 1

      while (true) {
        const logFile = path.join(logDirectory, `${date}_${run}.log`)
        try {
          const descriptor = fs.openSync(logFile, 'wx')
          fs.closeSync(descriptor)
          return logFile
        } catch (error) {
          if (error.code !== 'EEXIST') throw error
          run += 1
        }
      }
    }

    function installConsoleLogger() {
      if (global[loggerStateKey]) return global[loggerStateKey]

      const inheritedLogFile = process.env.DAB_LOG_FILE
      const logFile = inheritedLogFile
        ? path.resolve(inheritedLogFile)
        : reserveRunFile(path.join(__dirname, 'log'))

      fs.mkdirSync(path.dirname(logFile), { recursive: true })
      process.env.DAB_LOG_FILE = logFile

      const streams = [process.stdout, process.stderr]
      const originalWrites = streams.map(stream => stream.write.bind(stream))

      streams.forEach((stream, index) => {
        const originalWrite = originalWrites[index]
        stream.write = function writeAndLog(chunk, encoding, callback) {
          const result = originalWrite(chunk, encoding, callback)
          try {
            const data = Buffer.isBuffer(chunk)
              ? chunk
              : Buffer.from(String(chunk), typeof encoding === 'string' ? encoding : 'utf8')
            fs.appendFileSync(logFile, data)
          } catch (error) {
            originalWrites[1](`[Logger] Could not write to ${logFile}: ${error.message}\n`)
          }
          return result
        }
      })

      const state = {
        logFile,
        restore() {
          streams.forEach((stream, index) => {
            stream.write = originalWrites[index]
          })
          delete global[loggerStateKey]
        }
      }
      global[loggerStateKey] = state

      console.log(`[Logger] Writing console output to ${path.relative(__dirname, logFile)}`)
      return state
    }

    module.exports = {
      installConsoleLogger,
      localDateKey
    }

    """#

    static let dataJSON = #"""
    {
      "discord": {
        "servers": {},
        "members": {},
        "users": {}
      },
      "blocks": {},
      "custom": {}
    }

    """#

    static let configJSON = configJSON(applicationName: "My Discord Bot")

    static func configJSON(applicationName: String, applicationVersion: String = "1.0.0") -> String {
        let config: [String: Any] = [
            "application": [
                "name": applicationName,
                "version": applicationVersion
            ],
            "commands": [
                "defaultPrefix": "!",
                "serverPrefixes": [:]
            ],
            "owners": []
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: config,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else {
            return "{}\n"
        }
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    static let intents = #"""
    Guilds
    GuildMembers
    GuildModeration
    GuildExpressions
    GuildIntegrations
    GuildWebhooks
    GuildInvites
    GuildVoiceStates
    GuildPresences
    GuildMessages
    GuildMessageReactions
    GuildMessageTyping
    DirectMessages
    DirectMessageReactions
    DirectMessageTyping
    MessageContent
    GuildScheduledEvents
    AutoModerationConfiguration
    AutoModerationExecution

    """#

    static let botRuntime = #"""
    'use strict'

    const { installConsoleLogger } = require('./logger')
    installConsoleLogger()

    const fs = require('fs')
    const path = require('path')
    const crypto = require('crypto')
    const DiscordJSModule = require('discord.js')
    const { Client, GatewayIntentBits, Partials } = DiscordJSModule
    const { readBotToken } = require('./token')

    const projectPath = __dirname
    try {
      process.chdir(projectPath)
    } catch (error) {
      throw new Error(`Could not use the bot root folder "${projectPath}": ${error.message}`)
    }
    const dataPath = path.join(projectPath, 'data', 'data.json')
    const configPath = path.join(projectPath, 'data', 'config.json')
    const rootConfigPath = path.join(projectPath, 'config')
    const workspacePath = path.join(projectPath, 'data', 'workspaces.json')

    function readJSON(file, fallback) {
      try {
        return JSON.parse(fs.readFileSync(file, 'utf8'))
      } catch (error) {
        console.error(`[Discord App Builder] Could not read ${path.relative(projectPath, file)}:`, error.message)
        return fallback
      }
    }

    function normalizeConfig(value) {
      const config = value && typeof value === 'object' ? value : {}
      const application = config.application && typeof config.application === 'object'
        ? config.application
        : {}
      const commands = config.commands && typeof config.commands === 'object'
        ? config.commands
        : {}
      return {
        ...config,
        application: {
          ...application,
          name: typeof application.name === 'string' && application.name.trim()
            ? application.name.trim()
            : path.basename(projectPath),
          version: typeof application.version === 'string' && application.version.trim()
            ? application.version.trim()
            : '1.0.0'
        },
        commands: {
          ...commands,
          defaultPrefix: typeof commands.defaultPrefix === 'string'
            ? commands.defaultPrefix
            : '!',
          serverPrefixes: commands.serverPrefixes && typeof commands.serverPrefixes === 'object'
            ? commands.serverPrefixes
            : {}
        },
        owners: Array.isArray(config.owners) ? config.owners : []
      }
    }

    class BotRuntime {
      constructor(client, groups) {
        this.client = client
        this.events = client
        this.console = (level, ...values) => {
          const method = String(level || 'log').toLowerCase()
          const normalizedMethod = method === 'success' ? 'log' : method
          const logger = typeof console[normalizedMethod] === 'function'
            ? console[normalizedMethod]
            : console.log
          logger(...values)
        }
        this.groups = groups
        this.lineValues = new Map()
        this.blocks = []
        this.Dependencies = {}
        this.pendingDependencies = []
        this._tempData = {}
        this.variables = new Map()
        this.DiscordJS = {
          client,
          module: DiscordJSModule
        }
        this.File = {
          paths: {
            project: projectPath,
            blocks: path.join(projectPath, 'blocks'),
            data: dataPath,
            config: configPath,
            rootConfig: rootConfigPath,
            token: path.join(projectPath, 'data', 'token.txt'),
            workspaces: workspacePath,
            log: path.join(projectPath, 'log')
          },
          writeFile: (file, value) => this.writeFile(file, value)
        }
        this.Config = normalizeConfig(readJSON(configPath, {
          application: { name: path.basename(projectPath), version: '1.0.0' },
          commands: { defaultPrefix: '!', serverPrefixes: {} },
          owners: []
        }))
        this.Data = {
          data: readJSON(dataPath, {
            discord: { servers: {}, members: {}, users: {} },
            blocks: {},
            custom: {}
          }),
          getData: (...args) => this.getData(...args),
          setData: (...args) => this.setData(...args),
          deleteData: (...args) => this.deleteData(...args),
          saveData: () => this.saveData(),
          workspaces: groups
        }
        Object.defineProperty(this.Data.data, ['d', 'b', 'b'].join(''), {
          value: {
            prefixes: {
              main: this.Config.commands.defaultPrefix,
              servers: this.Config.commands.serverPrefixes
            },
            owners: this.Config.owners
          },
          enumerable: false,
          configurable: true
        })
        this.Core = {
          typeof: value => this.valueType(value),
          require: name => this.require(name),
          console: (level, ...values) => this.console(level, ...values),
          setDependency: (name, blockName, value) => this.setDependency(name, blockName, value),
          generateID: length => this.generateID(length),
          restart: () => process.exit(0),
          end: details => this.end(details)
        }
        this.Blocks = {
          Data: this.Data,
          Core: this,
          inputs: {},
          cache: {}
        }
        global.Data = this.Data
        global.Config = this.Config
      }

      load() {
        for (const group of this.groups) {
          for (const workspace of group.workspaces || []) {
            if (workspace.active === false) continue
            for (const [index, block] of (workspace.blocks || []).entries()) {
              if (block.active === false) continue
              const file = path.join(projectPath, 'blocks', `${block.name}.js`)
              const cache = {
                workspace: workspace.id,
                workspaceID: workspace.id,
                workspaceName: workspace.info?.title || workspace.id,
                workspaceGroupID: group.id,
                workspaceGroupName: group.info?.title || group.id,
                blockID: block.block_id || block.id || `${workspace.id}:${index}`,
                name: block.name,
                index,
                inputs: block.inputs || {},
                options: block.options || {},
                outputs: block.outputs || {},
                _temp: {}
              }
              try {
                delete require.cache[require.resolve(file)]
                const definition = require(file)
                this.blocks.push({ definition, cache })
                this.Blocks.cache[block.name] = definition
                if (!this.Blocks.inputs[block.name]) this.Blocks.inputs[block.name] = {}
              } catch (error) {
                console.error(
                  `[Discord App Builder] Could not load block "${block.name}" (${this.blockContext(cache)}):`,
                  error
                )
              }
            }
          }
        }
      }

      async start() {
        console.log(
          `[Discord App Builder] Starting ${this.Config.application.name} v${this.Config.application.version}`
        )
        this.load()
        const token = readBotToken()
        const ready = this.client.isReady()
          ? Promise.resolve()
          : new Promise(resolve => this.client.once('ready', resolve))
        await this.client.login(token)
        await ready
        console.log(`[Discord App Builder] Logged in as ${this.client.user.tag}`)

        for (const item of this.blocks) {
          if (typeof item.definition.init !== 'function') continue
          try {
            await item.definition.init.call(this, this, item.cache.name)
          } catch (error) {
            console.error(
              `[Discord App Builder] Block "${item.cache.name}" failed to initialize (${this.blockContext(item.cache)}):`,
              error
            )
          }
        }
        await Promise.all(this.pendingDependencies)
        const automatic = this.blocks.filter(item => item.definition.auto_execute)
        const initialization = automatic.filter(item =>
          item.cache.name === 'bot_initialization_event' ||
          item.definition.name === 'Bot Initialization [Event]'
        )
        const beforeReady = automatic.filter(item => !initialization.includes(item))

        for (const item of beforeReady) {
          await this.execute(item)
        }
        for (const item of initialization) {
          await this.execute(item)
        }
      }

      async execute(item) {
        try {
          await item.definition.code.call(this, item.cache, this)
        } catch (error) {
          const missingInputs = this.missingRequiredInputs(item)
          const inputHint = missingInputs.length
            ? ` Missing required input values: ${missingInputs.join(', ')}.`
            : ''
          console.error(
            `[Discord App Builder] Block "${item.cache.name}" failed (${this.blockContext(item.cache)}).${inputHint}`,
            error
          )
        }
      }

      blockContext(cache) {
        return [
          `workspace="${cache.workspaceName || cache.workspace || 'unknown'}"`,
          `workspace_id="${cache.workspaceID || cache.workspace || 'unknown'}"`,
          `block_id="${cache.blockID || 'unknown'}"`,
          `block_index=${Number.isInteger(cache.index) ? cache.index + 1 : 'unknown'}`
        ].join(', ')
      }

      missingRequiredInputs(item) {
        const inputs = Array.isArray(item.definition?.inputs) ? item.definition.inputs : []
        return inputs
          .filter(input => input?.required)
          .filter(input => {
            const raw = item.cache.inputs[input.id]
            const wireIDs = Array.isArray(raw) ? raw : raw ? [raw] : []
            const hasWireValue = wireIDs.some(wireID =>
              this.hasLineValue(wireID, item.cache) &&
              this.getLineValue(wireID, item.cache) !== undefined &&
              this.getLineValue(wireID, item.cache) !== null
            )
            if (hasWireValue) return false
            const optionValue = this.GetOptionValue(input.id, item.cache)
            return optionValue === undefined || optionValue === null || optionValue === ''
          })
          .map(input => `"${input.name || input.id}" (${input.id})`)
      }

      GetInputValue(id, cache, includeDetails = false, defaultValue) {
        const raw = cache.inputs[id]
        const wireIDs = Array.isArray(raw) ? raw : raw ? [raw] : []
        const values = wireIDs
          .filter(wireID => this.hasLineValue(wireID, cache))
          .map(wireID => this.getLineValue(wireID, cache))
          .filter(value => value !== undefined)
        if (Array.isArray(raw)) return values
        const optionValue = this.GetOptionValue(id, cache, false, defaultValue)
        const value = this.normalizeInputValue(
          id,
          cache,
          values.length ? values[0] : optionValue
        )
        if (includeDetails && value !== undefined) {
          return { value, type: this.valueType(value) }
        }
        return value
      }

      normalizeInputValue(id, cache, value) {
        if (id !== 'search_value' || typeof value !== 'string') return value
        const options = cache.options || {}
        const isIDLookup = Object.entries(options).some(([key, selection]) =>
          key.startsWith('find_') && key.endsWith('_by') && selection === 'id'
        )
        return isIDLookup ? value.trim() : value
      }

      GetOptionValue(id, cache, includeDetails = false, defaultValue) {
        let value = cache.options[id]
        if (value === undefined && id === 'text') value = cache.options.source_text
        if (value === undefined && id === 'source_text') value = cache.options.text
        if (value === undefined) value = defaultValue
        if (includeDetails && value !== undefined) {
          return { value, type: this.valueType(value) }
        }
        return value
      }

      lineValueKey(wireID, cache = {}) {
        const workspaceID = cache.workspaceID || cache.workspace
        return workspaceID ? `${workspaceID}\u0000${wireID}` : String(wireID)
      }

      hasLineValue(wireID, cache = {}) {
        const scopedKey = this.lineValueKey(wireID, cache)
        return this.lineValues.has(scopedKey) || (
          scopedKey !== String(wireID) && this.lineValues.has(String(wireID))
        )
      }

      getLineValue(wireID, cache = {}) {
        const scopedKey = this.lineValueKey(wireID, cache)
        if (this.lineValues.has(scopedKey)) return this.lineValues.get(scopedKey)
        return this.lineValues.get(String(wireID))
      }

      setLineValue(wireID, value, cache = {}) {
        this.lineValues.set(this.lineValueKey(wireID, cache), value)
        return value
      }

      deleteLineValue(wireID, cache = {}) {
        const scopedKey = this.lineValueKey(wireID, cache)
        const removedScoped = this.lineValues.delete(scopedKey)
        const removedFallback = scopedKey === String(wireID)
          ? false
          : this.lineValues.delete(String(wireID))
        return removedScoped || removedFallback
      }

      ConvertRegex(value, flags) {
        if (value instanceof RegExp) {
          return flags === undefined ? value : new RegExp(value.source, flags)
        }
        if (typeof value !== 'string') return value

        const match = value.match(/^\/([\s\S]*)\/([dgimsuvy]*)$/)
        if (!match) return value
        return new RegExp(match[1], flags === undefined ? match[2] : flags)
      }

      StoreOutputValue(value, id, cache) {
        const raw = cache.outputs[id]
        const wireIDs = Array.isArray(raw) ? raw : raw ? [raw] : []
        if (value === undefined && wireIDs.length) {
          console.warn(
            `[Discord App Builder] Block "${cache.name}" produced undefined on connected output "${id}" (${this.blockContext(cache)}).`
          )
        }
        for (const wireID of wireIDs) {
          this.setLineValue(wireID, value, cache)
        }
        return value
      }

      RunNextBlock(id, cache) {
        const raw = cache.outputs[id]
        const wireIDs = Array.isArray(raw) ? raw : raw ? [raw] : []
        const sourceWorkspaceID = cache.workspaceID || cache.workspace
        const next = this.blocks.filter(item => {
          const targetWorkspaceID = item.cache.workspaceID || item.cache.workspace
          if (sourceWorkspaceID && targetWorkspaceID !== sourceWorkspaceID) {
            return false
          }
          return Object.values(item.cache.inputs).some(input => {
            const inputIDs = Array.isArray(input) ? input : input ? [input] : []
            return inputIDs.some(wireID => wireIDs.includes(wireID))
          })
        })
        return Promise.all(next.map(item => this.execute(item)))
      }

      findWorkspaces(searchType, searchValue) {
        const entries = []
        for (const [groupIndex, group] of this.groups.entries()) {
          for (const [workspaceIndex, workspace] of (group.workspaces || []).entries()) {
            entries.push({ group, groupIndex, workspace, workspaceIndex })
          }
        }

        switch (String(searchType || '')) {
          case 'id':
            return entries
              .filter(entry => String(entry.workspace.id) === String(searchValue))
              .map(entry => entry.workspace)
          case 'groupId':
            return entries
              .filter(entry => String(entry.group.id) === String(searchValue))
              .map(entry => entry.workspace)
          case 'number': {
            const number = Number.parseInt(searchValue, 10)
            if (!Number.isInteger(number)) return []
            return entries
              .filter((entry, index) =>
                index + 1 === number || entry.workspaceIndex + 1 === number
              )
              .map(entry => entry.workspace)
          }
          case 'title':
            return entries
              .filter(entry => entry.workspace.info?.title === searchValue)
              .map(entry => entry.workspace)
          case 'description':
            return entries
              .filter(entry => entry.workspace.info?.description === searchValue)
              .map(entry => entry.workspace)
          default:
            return []
        }
      }

      Emitter(id, settings = {}, sourceCache = {}) {
        const emitterID = String(id).trim()
        const restriction = String(settings.restriction_type || 'all')
        let allowedWorkspaceIDs

        if (restriction === 'current') {
          allowedWorkspaceIDs = new Set([
            sourceCache.workspaceID || sourceCache.workspace
          ].filter(Boolean))
        } else if (restriction === 'specific') {
          allowedWorkspaceIDs = new Set(
            this.findWorkspaces(settings.search_type, settings.search_value)
              .map(workspace => workspace.id)
          )
        }

        const receivers = this.blocks.filter(item => {
          const isReceiver = [item.cache.name, item.definition?.name]
            .filter(Boolean)
            .some(name => String(name).toLowerCase().startsWith('receiver'))
          if (!isReceiver) return false
          const workspaceID = item.cache.workspaceID || item.cache.workspace
          if (allowedWorkspaceIDs && !allowedWorkspaceIDs.has(workspaceID)) return false
          const receiverID = this.GetInputValue('id', item.cache)
          if (Array.isArray(receiverID)) {
            return receiverID.some(value => String(value).trim() === emitterID)
          }
          return receiverID !== undefined && String(receiverID).trim() === emitterID
        })

        if (!receivers.length) {
          console.warn(
            `[Discord App Builder] Emitter found no receiver for id="${emitterID}" (${this.blockContext(sourceCache)}).`
          )
        }
        const values = Array.isArray(settings.values) ? settings.values : []
        return Promise.all(receivers.map(item => {
          const receiverCache = {
            ...item.cache,
            inputs: { ...item.cache.inputs },
            options: { ...item.cache.options },
            outputs: { ...item.cache.outputs },
            _temp: { ...item.cache._temp, __VALUES: [...values] }
          }
          return this.execute({ definition: item.definition, cache: receiverCache })
        }))
      }

      emitter(...args) {
        return this.Emitter(...args)
      }

      isOutputConnected(id, cache) {
        const raw = cache.outputs[id]
        return Array.isArray(raw) ? raw.length > 0 : Boolean(raw)
      }

      async require(name) {
        try {
          return require(name)
        } catch (error) {
          if (error.code === 'ERR_REQUIRE_ESM') return import(name)
          throw error
        }
      }

      writeFile(file, value) {
        const target = path.isAbsolute(file) ? file : path.resolve(projectPath, file)
        fs.mkdirSync(path.dirname(target), { recursive: true })
        const contents = typeof value === 'string' || Buffer.isBuffer(value)
          ? value
          : JSON.stringify(value, null, 2)
        fs.writeFileSync(target, contents)
        try {
          delete require.cache[require.resolve(target)]
        } catch {}
        return target
      }

      setDependency(name, blockName, value) {
        if (Object.prototype.hasOwnProperty.call(this.Dependencies, name)) {
          return this.Dependencies[name]
        }
        const dependency = typeof value === 'function' ? value() : value
        if (dependency && typeof dependency.then === 'function') {
          const pending = dependency.then(resolved => {
            this.Dependencies[name] = resolved
            return resolved
          })
          this.Dependencies[name] = pending
          this.pendingDependencies.push(pending)
          return pending
        }
        this.Dependencies[name] = dependency
        return dependency
      }

      generateID(length = 16) {
        const size = Math.max(1, Number.parseInt(length, 10) || 16)
        return crypto.randomBytes(Math.ceil(size * 0.75)).toString('base64url').slice(0, size)
      }

      getDependency(name) {
        return this.Dependencies[name]
      }

      valueType(value) {
        if (Array.isArray(value)) return 'array'
        if (value === null) return 'null'
        if (value instanceof Date) return 'date'
        return typeof value
      }

      getBuilder() {
        return this
      }

      getData(name, target, type = 'custom') {
        const bucket = this.dataBucket(type, target, false)
        return bucket ? bucket[name] : undefined
      }

      setData(name, value, target, type = 'custom') {
        const bucket = this.dataBucket(type, target, true)
        if (value === undefined) delete bucket[name]
        else bucket[name] = value
        this.saveData()
        return value
      }

      deleteData(name, target, type = 'custom') {
        const bucket = this.dataBucket(type, target, false)
        if (!bucket) return false
        const existed = Object.prototype.hasOwnProperty.call(bucket, name)
        delete bucket[name]
        if (existed) this.saveData()
        return existed
      }

      dataBucket(type, target, create) {
        const data = this.Data.data
        if (type === 'block') {
          if (create && !data.blocks[target || 'global']) data.blocks[target || 'global'] = {}
          return data.blocks[target || 'global']
        }
        if (type === 'server' || type === 'member' || type === 'user') {
          const key = type === 'server' ? 'servers' : `${type}s`
          if (create && !data.discord[key][target || 'global']) data.discord[key][target || 'global'] = {}
          return data.discord[key][target || 'global']
        }
        if (target) {
          if (create && !data.custom[target]) data.custom[target] = {}
          return data.custom[target]
        }
        return data.custom
      }

      saveData() {
        fs.writeFileSync(dataPath, JSON.stringify(this.Data.data, null, 2))
      }

      getConfig(key, fallback) {
        if (!key) return this.Config
        const pathParts = Array.isArray(key) ? key : String(key).split('.')
        let value = this.Config
        for (const part of pathParts) {
          if (!value || typeof value !== 'object' || !(part in value)) return fallback
          value = value[part]
        }
        return value
      }

      saveConfig() {
        fs.writeFileSync(configPath, JSON.stringify(this.Config, null, 2))
      }

      setPrefix(prefix, serverID = false) {
        const value = String(prefix)
        if (serverID) {
          this.Config.commands.serverPrefixes[String(serverID)] = value
        } else {
          this.Config.commands.defaultPrefix = value
        }
        const legacy = this.Data.data[['d', 'b', 'b'].join('')]
        legacy.prefixes.main = this.Config.commands.defaultPrefix
        legacy.prefixes.servers = this.Config.commands.serverPrefixes
        this.saveConfig()
        return value
      }

      changeOwners(owners, action = 'set') {
        const values = (Array.isArray(owners) ? owners : [owners])
          .map(owner => owner && typeof owner === 'object' ? owner.id : owner)
          .filter(owner => owner !== undefined && owner !== null && String(owner).length)
          .map(String)
        const next = action === 'add'
          ? [...new Set([...this.Config.owners, ...values])]
          : [...new Set(values)]
        this.Config.owners = next
        this.Data.data[['d', 'b', 'b'].join('')].owners = next
        this.saveConfig()
        return next
      }

      getServerQueue(server) {
        const dependency = this.Dependencies.DiscordPlayer
        if (!dependency || typeof dependency.then === 'function') return undefined
        const player = dependency.player
        const serverID = server && typeof server === 'object' ? server.id : server
        return player?.nodes?.get?.(serverID) ?? player?.getQueue?.(serverID)
      }

      end(details) {
        const message = details && typeof details === 'object' ? details.message : details
        throw details instanceof Error
          ? details
          : new Error(message || 'A block stopped the bot runtime.')
      }

      variableKey(name, settings = {}, cache = {}) {
        return [
          settings.type || 'global',
          settings.restriction || '',
          settings.index || '',
          cache.workspace || '',
          name
        ].join(':')
      }

      getVariable(name, settings, cache) {
        return this.variables.get(this.variableKey(name, settings, cache))
      }

      setVariable(name, value, settings, cache) {
        this.variables.set(this.variableKey(name, settings, cache), value)
        return value
      }

      deleteVariable(name, settings, cache) {
        this.variables.delete(this.variableKey(name, settings, cache))
      }

      error(message) {
        console.error('[Discord App Builder]', message)
      }
    }

    Object.defineProperty(BotRuntime.prototype, ['get', 'D', 'B', 'B'].join(''), {
      value: BotRuntime.prototype.getBuilder
    })

    const intents = Object.values(GatewayIntentBits).filter(value => Number.isInteger(value))
    const client = new Client({
      intents,
      partials: Object.values(Partials).filter(value => Number.isInteger(value))
    })
    const groups = readJSON(workspacePath, [])
    const runtime = new BotRuntime(client, groups)
    if (require.main === module) {
      runtime.start().catch(error => {
        console.error('[Discord App Builder] Bot failed to start:', error)
        process.exitCode = 1
      })
    }

    module.exports = { BotRuntime }

    """#

    static let initializationBlock = #"""
    module.exports = {
      name: "Bot Initialization [Event]",
      description: "Runs when the Discord client is ready.",
      category: "Events",
      auto_execute: true,
      inputs: [],
      options: [],
      outputs: [
        {
          id: "action",
          name: "Action",
          description: "Executes the following blocks.",
          types: ["action"]
        }
      ],
      code(cache) {
        this.RunNextBlock("action", cache)
      }
    }

    """#

    static let textBlock = #"""
    module.exports = {
      name: "Text",
      description: "Stores a text value.",
      category: "Inputs",
      auto_execute: true,
      inputs: [],
      options: [
        {
          id: "text",
          name: "Text",
          description: "The text value.",
          type: "TEXT"
        }
      ],
      outputs: [
        {
          id: "text",
          name: "Text",
          description: "The stored text.",
          types: ["text"]
        }
      ],
      code(cache) {
        this.StoreOutputValue(this.GetOptionValue("text", cache), "text", cache)
      }
    }

    """#

    static let consoleLogBlock = #"""
    module.exports = {
      name: "Console Log",
      description: "Prints a value to the console.",
      category: "Utilities",
      auto_execute: false,
      inputs: [
        {
          id: "action",
          name: "Action",
          description: "Executes this block.",
          types: ["action"]
        },
        {
          id: "value",
          name: "Value",
          description: "The value to print.",
          types: ["unspecified", "text", "number", "boolean", "object", "list"]
        }
      ],
      options: [
        {
          id: "value",
          name: "Value",
          description: "Used when the input is not connected.",
          type: "TEXT"
        }
      ],
      outputs: [
        {
          id: "action",
          name: "Action",
          description: "Executes the following blocks.",
          types: ["action"]
        }
      ],
      code(cache) {
        console.log(this.GetInputValue("value", cache))
        this.RunNextBlock("action", cache)
      }
    }

    """#
}
