import Foundation
import Testing
@testable import DiscordAppBuilder

struct ProjectStoreTests {
    @Test func createsCompleteProjectScaffold() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appending(path: "DiscordAppBuilderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let store = try ProjectStore.createProject(at: projectURL)
        let expectedFiles = [
            "bot.js",
            "sharding.js",
            "logger.js",
            "token.js",
            "package.json",
            "blocks/bot_initialization_event.js",
            "blocks/text.js",
            "blocks/console_log.js",
            "data/data.json",
            "data/config.json",
            "data/token.txt",
            "data/INTENTS.txt",
            "config/server.txt",
            "config/log.txt",
            "data/workspaces.json"
        ]

        for relativePath in expectedFiles {
            #expect(FileManager.default.fileExists(atPath: projectURL.appending(path: relativePath).path))
        }
        #expect(store.workspaceReferences.count == 1)

        let packageData = try Data(contentsOf: projectURL.appending(path: "package.json"))
        let package = try #require(
            JSONSerialization.jsonObject(with: packageData) as? [String: Any]
        )
        let dependencies = try #require(package["dependencies"] as? [String: String])
        #expect(dependencies == [
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
        ])

        #expect(!FileManager.default.fileExists(atPath: projectURL.appending(path: "data/workspace.json").path))

        let configData = try Data(contentsOf: projectURL.appending(path: "data/config.json"))
        let config = try #require(
            JSONSerialization.jsonObject(with: configData) as? [String: Any]
        )
        let commands = try #require(config["commands"] as? [String: Any])
        let application = try #require(config["application"] as? [String: Any])
        #expect(application["name"] as? String == projectURL.lastPathComponent)
        #expect(application["version"] as? String == "1.0.0")
        #expect(commands["defaultPrefix"] as? String == "!")
        #expect(commands["serverPrefixes"] as? [String: String] == [:])
        #expect(config["owners"] as? [String] == [])

        for script in ["bot.js", "sharding.js", "logger.js", "token.js"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["node", "--check", projectURL.appending(path: script).path]
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }

        let botRuntime = try String(
            contentsOf: projectURL.appending(path: "bot.js"),
            encoding: .utf8
        )
        #expect(botRuntime.contains("this.File = {"))
        #expect(botRuntime.contains("workspaces: workspacePath"))
        #expect(botRuntime.contains("process.chdir(projectPath)"))
        #expect(botRuntime.contains("rootConfig: rootConfigPath"))
        #expect(botRuntime.contains("this.DiscordJS = {"))
        #expect(botRuntime.contains("await ready"))
        #expect(botRuntime.contains("workspaces: groups"))
        #expect(botRuntime.contains("ConvertRegex(value, flags)"))
        #expect(botRuntime.contains("module.exports = { BotRuntime }"))
        #expect(
            botRuntime.contains(
                "Starting ${this.Config.application.name} v${this.Config.application.version}"
            )
        )

        let splitBlockURL = URL(
            fileURLWithPath: "/private/tmp/pal-blocks-reference/blocks/split_text.js"
        )
        if FileManager.default.fileExists(atPath: splitBlockURL.path) {
            let moduleDirectory = projectURL.appending(
                path: "node_modules/discord.js",
                directoryHint: .isDirectory
            )
            try FileManager.default.createDirectory(
                at: moduleDirectory,
                withIntermediateDirectories: true
            )
            let fakeDiscordModule = """
            const { EventEmitter } = require('events')
            class Client extends EventEmitter {}
            class ActionRowBuilder {
              addComponents() { return this }
            }
            module.exports = {
              ActionRowBuilder,
              Client,
              GatewayIntentBits: { Guilds: 1 },
              MessageFlags: { SuppressNotifications: 4096 },
              Partials: { Channel: 1 }
            }
            """
            try Data(fakeDiscordModule.utf8).write(
                to: moduleDirectory.appending(path: "index.js"),
                options: .atomic
            )
            let betterSendBlockURL = splitBlockURL.deletingLastPathComponent()
                .appending(path: "better_send_message.js")
            let localBetterSendBlockURL = projectURL
                .appending(path: "blocks/better_send_message.js")
            try FileManager.default.copyItem(
                at: betterSendBlockURL,
                to: localBetterSendBlockURL
            )

            let compatibilityProcess = Process()
            compatibilityProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            compatibilityProcess.currentDirectoryURL = FileManager.default.temporaryDirectory
            compatibilityProcess.arguments = [
                "node",
                "-e",
                #"""
                ;(async () => {
                  const { BotRuntime } = require(process.argv[3])
                  const fs = require('fs')
                  if (fs.realpathSync(process.cwd()) !== fs.realpathSync(process.argv[4])) {
                    process.exit(12)
                  }
                  const split = require(process.argv[1])
                  const betterSend = require(process.argv[2])
                  const emitter8 = require(process.argv[5])
                  const receiver8 = require(process.argv[6])
                  const textBlock = require(process.argv[7])
                  const runtime = new BotRuntime({}, [])
                  const cache = {
                    name: 'split_text',
                    workspace: 'test',
                    inputs: {
                      text: 'text-wire',
                      separator: 'separator-wire',
                      limit: 'limit-wire'
                    },
                    options: {},
                    outputs: { list: 'list-wire', action: [] },
                    _temp: {}
                  }
                  runtime.lineValues.set('text-wire', 'one two three')
                  runtime.lineValues.set('separator-wire', '/\\s+/')
                  runtime.lineValues.set('limit-wire', 2)
                  split.code.call(runtime, cache, runtime)
                  const result = runtime.getLineValue('list-wire', cache)
                  if (JSON.stringify(result) !== JSON.stringify(['one', 'two'])) process.exit(2)
                  if (runtime.ConvertRegex('.') !== '.') process.exit(3)
                  if (runtime.Core.typeof([]) !== 'array') process.exit(4)
                  runtime.lineValues.set('id-wire', '123456789\n')
                  const normalizedID = runtime.GetInputValue('search_value', {
                    inputs: { search_value: 'id-wire' },
                    options: { find_channel_by: 'id' }
                  })
                  if (normalizedID !== '123456789') process.exit(14)

                  let errorHeading = ''
                  const originalError = console.error
                  console.error = (...values) => { errorHeading = String(values[0]) }
                  await runtime.execute({
                    definition: {
                      inputs: [{ id: 'channel', name: 'Channel / Message', required: true }],
                      code() { throw new Error('probe failure') }
                    },
                    cache: {
                      name: 'failure_probe',
                      workspace: 'workspace-id',
                      workspaceID: 'workspace-id',
                      workspaceName: 'Error Test Workspace',
                      blockID: 'workspace-id:7',
                      index: 7,
                      inputs: { channel: 'missing-channel-wire' },
                      options: {},
                      outputs: {},
                      _temp: {}
                    }
                  })
                  console.error = originalError
                  if (!errorHeading.includes('workspace="Error Test Workspace"')) process.exit(5)
                  if (!errorHeading.includes('workspace_id="workspace-id"')) process.exit(6)
                  if (!errorHeading.includes('block_id="workspace-id:7"')) process.exit(7)
                  if (!errorHeading.includes('block_index=8')) process.exit(8)
                  if (!errorHeading.includes('"Channel / Message" (channel)')) process.exit(9)

                  let sentPayload
                  const sendCache = {
                    name: 'better_send_message',
                    workspace: 'workspace-id',
                    workspaceID: 'workspace-id',
                    workspaceName: 'Source Text Test',
                    blockID: 'workspace-id:14',
                    index: 14,
                    inputs: {
                      channel: 'channel-wire',
                      text: ['text-wire'],
                      embed: [],
                      file: [],
                      row: []
                    },
                    options: {
                      type: 'send',
                      silent: 'undefined',
                      source_text: 'Hello ${text1}\\nDone'
                    },
                    outputs: { action: [], message: [], error: [] },
                    _temp: {}
                  }
                  runtime.lineValues.set('channel-wire', {
                    send(payload) {
                      sentPayload = payload
                      return Promise.resolve({ id: 'sent-message' })
                    }
                  })
                  runtime.lineValues.set('text-wire', 'world')
                  await betterSend.code.call(runtime, sendCache, runtime)
                  await new Promise(resolve => setImmediate(resolve))
                  if (sentPayload?.content !== 'Hello world\nDone') process.exit(10)

                  const receiverCache = {
                    name: 'receiver 8x',
                    workspace: 'receiver-workspace',
                    workspaceID: 'receiver-workspace',
                    workspaceName: 'Receiver Workspace',
                    blockID: 'receiver-workspace:1',
                    index: 1,
                    inputs: { id: 'receiver-id-wire' },
                    options: {},
                    outputs: {
                      action: ['shared-action-wire'],
                      value1: ['received-value-wire'],
                      value2: ['received-list-wire'],
                      value3: [],
                      value4: [],
                      value5: [],
                      value6: [],
                      value7: [],
                      value8: []
                    },
                    _temp: {}
                  }
                  const otherReceiverCache = {
                    ...receiverCache,
                    workspace: 'other-receiver-workspace',
                    workspaceID: 'other-receiver-workspace',
                    workspaceName: 'Other Receiver Workspace',
                    blockID: 'other-receiver-workspace:1',
                    outputs: {
                      ...receiverCache.outputs,
                      value1: ['received-value-wire'],
                      value2: ['received-list-wire']
                    },
                    _temp: {}
                  }
                  const receiverStarts = []
                  const followupDefinition = {
                    name: 'Receiver Followup',
                    inputs: [{ id: 'action', name: 'Action', types: ['action'] }],
                    code(cache) { receiverStarts.push(cache.workspaceID) }
                  }
                  runtime.blocks = [
                    { definition: receiver8, cache: receiverCache },
                    { definition: receiver8, cache: otherReceiverCache },
                    {
                      definition: followupDefinition,
                      cache: {
                        name: 'receiver_followup',
                        workspace: 'receiver-workspace',
                        workspaceID: 'receiver-workspace',
                        inputs: { action: 'shared-action-wire' },
                        options: {},
                        outputs: {},
                        _temp: {}
                      }
                    },
                    {
                      definition: followupDefinition,
                      cache: {
                        name: 'receiver_followup',
                        workspace: 'other-receiver-workspace',
                        workspaceID: 'other-receiver-workspace',
                        inputs: { action: 'shared-action-wire' },
                        options: {},
                        outputs: {},
                        _temp: {}
                      }
                    }
                  ]
                  await runtime.execute({
                    definition: textBlock,
                    cache: {
                      name: 'text',
                      workspace: 'receiver-workspace',
                      workspaceID: 'receiver-workspace',
                      inputs: {},
                      options: { text: 'pluralapp' },
                      outputs: { text: ['receiver-id-wire'] },
                      _temp: {}
                    }
                  })
                  await runtime.execute({
                    definition: textBlock,
                    cache: {
                      name: 'text',
                      workspace: 'other-receiver-workspace',
                      workspaceID: 'other-receiver-workspace',
                      inputs: {},
                      options: { text: 'otherapp' },
                      outputs: { text: ['receiver-id-wire'] },
                      _temp: {}
                    }
                  })
                  const emittedObject = {
                    id: 'discord-channel',
                    send() { return 'sent' }
                  }
                  const emittedList = [emittedObject, { id: 'discord-server' }]
                  const emitterCache = {
                    name: 'emitter 8x',
                    workspace: 'source-workspace',
                    workspaceID: 'source-workspace',
                    workspaceName: 'Source Workspace',
                    blockID: 'source-workspace:2',
                    index: 2,
                    inputs: {
                      id: 'emitter-id-wire',
                      value1: 'emitted-object-wire',
                      value2: 'emitted-list-wire'
                    },
                    options: {
                      restriction_type: 'all',
                      search_type: 'number'
                    },
                    outputs: { action: [] },
                    _temp: {}
                  }
                  runtime.setLineValue('emitter-id-wire', 'pluralapp', emitterCache)
                  runtime.setLineValue('emitted-object-wire', emittedObject, emitterCache)
                  runtime.setLineValue('emitted-list-wire', emittedList, emitterCache)
                  await emitter8.code.call(runtime, emitterCache, runtime)
                  await new Promise(resolve => setImmediate(resolve))
                  if (runtime.getLineValue('received-value-wire', receiverCache) !== emittedObject) {
                    process.exit(15)
                  }
                  if (runtime.getLineValue('received-list-wire', receiverCache) !== emittedList) {
                    process.exit(17)
                  }
                  if (runtime.hasLineValue('received-value-wire', otherReceiverCache)) process.exit(18)
                  if (JSON.stringify(receiverStarts) !== JSON.stringify(['receiver-workspace'])) {
                    process.exit(19)
                  }

                  runtime.deleteLineValue('received-value-wire', receiverCache)
                  emitterCache.options.restriction_type = 'current'
                  await emitter8.code.call(runtime, emitterCache, runtime)
                  await new Promise(resolve => setImmediate(resolve))
                  if (runtime.hasLineValue('received-value-wire', receiverCache)) process.exit(16)
                })().catch(error => {
                  console.error(error)
                  process.exit(13)
                })
                """#,
                splitBlockURL.path,
                localBetterSendBlockURL.path,
                projectURL.appending(path: "bot.js").path,
                projectURL.path,
                splitBlockURL.deletingLastPathComponent()
                  .appending(path: "emitter 8x.js").path,
                splitBlockURL.deletingLastPathComponent()
                  .appending(path: "receiver 8x.js").path,
                splitBlockURL.deletingLastPathComponent()
                  .appending(path: "text.js").path
            ]
            try compatibilityProcess.run()
            compatibilityProcess.waitUntilExit()
            #expect(compatibilityProcess.terminationStatus == 0)
            try? FileManager.default.removeItem(at: projectURL.appending(path: "log"))
        }

        for generatedFile in ["package.json", "bot.js", "sharding.js", "logger.js", "token.js"] {
            let contents = try String(
                contentsOf: projectURL.appending(path: generatedFile),
                encoding: .utf8
            )
            let legacyInitials = ["D", "B", "B"].joined()
            let legacyName = ["Discord", "Bot", "Builder"].joined(separator: " ")
            #expect(!contents.contains(legacyInitials))
            #expect(!contents.localizedCaseInsensitiveContains(legacyName))
        }

        let tokenURL = projectURL.appending(path: "data/token.txt")
        #expect(try String(contentsOf: tokenURL, encoding: .utf8) == "")

        let emptyTokenProcess = Process()
        emptyTokenProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        emptyTokenProcess.currentDirectoryURL = projectURL
        emptyTokenProcess.arguments = [
            "node",
            "-e",
            "try { require('./token').readBotToken(); process.exit(2) } catch (error) { if (!error.message.includes('is empty')) process.exit(3) }"
        ]
        try emptyTokenProcess.run()
        emptyTokenProcess.waitUntilExit()
        #expect(emptyTokenProcess.terminationStatus == 0)

        try FileManager.default.removeItem(at: tokenURL)
        let missingTokenProcess = Process()
        missingTokenProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        missingTokenProcess.currentDirectoryURL = projectURL
        missingTokenProcess.arguments = [
            "node",
            "-e",
            "try { require('./token').readBotToken(); process.exit(2) } catch (error) { if (!error.message.includes('is missing')) process.exit(3) }"
        ]
        try missingTokenProcess.run()
        missingTokenProcess.waitUntilExit()
        #expect(missingTokenProcess.terminationStatus == 0)

        try Data("discord.bot.token".utf8).write(to: tokenURL, options: .atomic)

        let tokenProcess = Process()
        tokenProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        tokenProcess.currentDirectoryURL = projectURL
        tokenProcess.arguments = [
            "node",
            "-e",
            "if (require('./token').readBotToken() !== 'discord.bot.token') process.exit(1)"
        ]
        try tokenProcess.run()
        tokenProcess.waitUntilExit()
        #expect(tokenProcess.terminationStatus == 0)

        for run in 1...2 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.currentDirectoryURL = projectURL
            process.arguments = [
                "node",
                "-e",
                "require('./logger').installConsoleLogger(); console.log('test run \(run)'); console.error('test error \(run)')"
            ]
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }

        let logFiles = try FileManager.default.contentsOfDirectory(
            at: projectURL.appending(path: "log"),
            includingPropertiesForKeys: nil
        )
        .map(\.lastPathComponent)
        .sorted()
        #expect(logFiles.count == 2)
        #expect(logFiles[0].hasSuffix("_1.log"))
        #expect(logFiles[1].hasSuffix("_2.log"))

        let firstLog = try String(
            contentsOf: projectURL.appending(path: "log/\(logFiles[0])"),
            encoding: .utf8
        )
        let secondLog = try String(
            contentsOf: projectURL.appending(path: "log/\(logFiles[1])"),
            encoding: .utf8
        )
        #expect(firstLog.contains("test run 1"))
        #expect(firstLog.contains("test error 1"))
        #expect(secondLog.contains("test run 2"))
        #expect(secondLog.contains("test error 2"))
    }

    @Test func importsCompleteWorkspacesFileIntoProject() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appending(path: "DiscordAppBuilderImport-\(UUID().uuidString)", directoryHint: .isDirectory)
        let importURL = FileManager.default.temporaryDirectory
            .appending(path: "workspaces-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: projectURL)
            try? FileManager.default.removeItem(at: importURL)
        }

        let importedData = """
        [
          {
            "id": "group00001",
            "info": { "title": "Imported Group", "collapsed": false },
            "workspaces": [
              {
                "id": "workspace01",
                "active": true,
                "info": {
                  "title": "Commands",
                  "description": "",
                  "thumbnail": ""
                },
                "blocks": [],
                "notes": []
              },
              {
                "id": "workspace02",
                "active": true,
                "info": {
                  "title": "Events",
                  "description": "",
                  "thumbnail": ""
                },
                "blocks": [],
                "notes": []
              }
            ]
          }
        ]
        """.data(using: .utf8)!
        try importedData.write(to: importURL)

        var store = try ProjectStore.createProject(at: projectURL)
        try store.importWorkspaces(from: importURL)

        #expect(store.groups.count == 1)
        #expect(store.workspaceReferences.map(\.title) == ["Commands", "Events"])

        let reopened = try ProjectStore.openProject(at: projectURL)
        #expect(reopened.groups.first?.info.title == "Imported Group")
        #expect(reopened.workspaceReferences.count == 2)
    }

    @Test func persistsDiscordStyleCategoriesAndWorkspaceMembership() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appending(path: "DiscordAppBuilderCategories-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: projectURL) }

        var store = try ProjectStore.createProject(at: projectURL)
        let category = store.addCategory(named: "Moderation")
        let workspace = store.addWorkspace(named: "audit-log", to: category.id)
        store.setCategory(category.id, collapsed: true)
        store.renameCategory(category.id, to: "Staff Tools")
        store.renameWorkspace(workspace.workspaceID, to: "staff-audit")
        try store.save()

        let reopened = try ProjectStore.openProject(at: projectURL)
        let savedCategory = try #require(reopened.groups.first(where: { $0.id == category.id }))
        #expect(savedCategory.info.title == "Staff Tools")
        #expect(savedCategory.info.collapsed)
        #expect(savedCategory.workspaces.map(\.info.title) == ["staff-audit"])
    }

    @Test func renamesBlockFileAcrossEveryWorkspace() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appending(path: "DiscordAppBuilderRename-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: projectURL) }

        var store = try ProjectStore.createProject(at: projectURL)
        let firstWorkspaceID = try #require(store.workspaceReferences.first?.workspaceID)
        let secondWorkspace = store.addWorkspace(named: "Second Workspace")
        let definition = try BlockParser().parseFile(
            projectURL.appending(path: "blocks/console_log.js")
        )
        let document = WorkflowDocument(
            name: "Renamed Blocks",
            blocks: [
                WorkflowBlock(
                    definition: definition,
                    position: CGPoint(x: 200, y: 160),
                    optionValues: ["value": .string("Preserved")],
                    inputWireValues: [:],
                    blockFileName: "console_log"
                )
            ],
            connections: []
        )
        try store.save(document: document, workspaceID: firstWorkspaceID)
        try store.save(document: document, workspaceID: secondWorkspace.workspaceID)

        let renamed = try store.renameBlockFile(
            from: "console_log",
            to: "print_message.js"
        )

        #expect(renamed == "print_message")
        #expect(
            !FileManager.default.fileExists(
                atPath: projectURL.appending(path: "blocks/console_log.js").path
            )
        )
        #expect(
            FileManager.default.fileExists(
                atPath: projectURL.appending(path: "blocks/print_message.js").path
            )
        )

        let reopened = try ProjectStore.openProject(at: projectURL)
        let storedNames = reopened.groups.flatMap(\.workspaces).flatMap(\.blocks).map(\.name)
        #expect(storedNames == ["print_message", "print_message"])

        var collisionWasRejected = false
        do {
            try store.renameBlockFile(from: "print_message", to: "text.js")
        } catch ProjectStoreError.blockFileAlreadyExists {
            collisionWasRejected = true
        }
        #expect(collisionWasRejected)
        #expect(
            FileManager.default.fileExists(
                atPath: projectURL.appending(path: "blocks/print_message.js").path
            )
        )
    }

    @Test func updatesBotRuntimeWithBackupAndPreservesProjectData() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appending(path: "DiscordAppBuilderRuntime-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let store = try ProjectStore.createProject(at: projectURL)
        let botURL = projectURL.appending(path: "bot.js")
        let loggerURL = projectURL.appending(path: "logger.js")
        let tokenHelperURL = projectURL.appending(path: "token.js")
        let tokenURL = projectURL.appending(path: "data/token.txt")
        let workspaceURL = projectURL.appending(path: "data/workspaces.json")
        let configURL = projectURL.appending(path: "data/config.json")
        let serverConfigURL = projectURL.appending(path: "config/server.txt")
        let logConfigURL = projectURL.appending(path: "config/log.txt")
        let workspaceBefore = try Data(contentsOf: workspaceURL)

        try Data("// customized runtime\n".utf8).write(to: botURL, options: .atomic)
        try Data("secret-token".utf8).write(to: tokenURL, options: .atomic)
        try Data("server-id".utf8).write(to: serverConfigURL, options: .atomic)
        try Data("channel-id".utf8).write(to: logConfigURL, options: .atomic)
        try Data(#"{"commands":{"defaultPrefix":"?","serverPrefixes":{}},"owners":["owner-id"]}"#.utf8)
            .write(to: configURL, options: .atomic)
        try FileManager.default.removeItem(at: loggerURL)
        try FileManager.default.removeItem(at: tokenHelperURL)

        let updatedBackupURL = try store.updateBotRuntime()
        let backupURL = try #require(updatedBackupURL)

        #expect(
            try String(contentsOf: botURL, encoding: .utf8) == ProjectTemplates.botRuntime
        )
        #expect(
            try String(contentsOf: backupURL, encoding: .utf8) == "// customized runtime\n"
        )
        #expect(FileManager.default.fileExists(atPath: loggerURL.path))
        #expect(FileManager.default.fileExists(atPath: tokenHelperURL.path))
        #expect(try String(contentsOf: tokenURL, encoding: .utf8) == "secret-token")
        #expect(try String(contentsOf: serverConfigURL, encoding: .utf8) == "server-id")
        #expect(try String(contentsOf: logConfigURL, encoding: .utf8) == "channel-id")
        let updatedConfigData = try Data(contentsOf: configURL)
        let updatedConfig = try #require(
            JSONSerialization.jsonObject(with: updatedConfigData) as? [String: Any]
        )
        let updatedApplication = try #require(
            updatedConfig["application"] as? [String: Any]
        )
        let updatedCommands = try #require(updatedConfig["commands"] as? [String: Any])
        #expect(updatedApplication["name"] as? String == projectURL.lastPathComponent)
        #expect(updatedApplication["version"] as? String == "1.0.0")
        #expect(updatedCommands["defaultPrefix"] as? String == "?")
        #expect(updatedConfig["owners"] as? [String] == ["owner-id"])
        #expect(try Data(contentsOf: workspaceURL) == workspaceBefore)

        var customizedConfig = updatedConfig
        customizedConfig["application"] = [
            "name": "Production Bot",
            "version": "2.4.1"
        ]
        try JSONSerialization.data(
            withJSONObject: customizedConfig,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: configURL, options: .atomic)

        _ = try store.updateBotRuntime()

        let preservedConfig = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any]
        )
        let preservedApplication = try #require(
            preservedConfig["application"] as? [String: Any]
        )
        #expect(preservedApplication["name"] as? String == "Production Bot")
        #expect(preservedApplication["version"] as? String == "2.4.1")
    }

    @Test func runtimeUpdateMigratesExistingCommandConfiguration() throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appending(path: "DiscordAppBuilderConfigMigration-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let store = try ProjectStore.createProject(at: projectURL)
        let dataURL = projectURL.appending(path: "data/data.json")
        let configURL = projectURL.appending(path: "data/config.json")
        let legacyKey = ["d", "b", "b"].joined()
        let existingData: [String: Any] = [
            "discord": ["servers": [:], "members": [:], "users": [:]],
            "blocks": [:],
            "custom": [:],
            legacyKey: [
                "prefixes": [
                    "main": "?",
                    "servers": ["server-id": "$"]
                ],
                "owners": ["owner-id"]
            ]
        ]
        try JSONSerialization.data(withJSONObject: existingData, options: [.prettyPrinted])
            .write(to: dataURL, options: .atomic)
        try FileManager.default.removeItem(at: configURL)

        _ = try store.updateBotRuntime()

        let configData = try Data(contentsOf: configURL)
        let config = try #require(
            JSONSerialization.jsonObject(with: configData) as? [String: Any]
        )
        let commands = try #require(config["commands"] as? [String: Any])
        let application = try #require(config["application"] as? [String: Any])
        #expect(application["name"] as? String == projectURL.lastPathComponent)
        #expect(application["version"] as? String == "1.0.0")
        #expect(commands["defaultPrefix"] as? String == "?")
        #expect((commands["serverPrefixes"] as? [String: String])?["server-id"] == "$")
        #expect(config["owners"] as? [String] == ["owner-id"])
    }

    @Test func readsCopiedSingleWorkspaceJSON() throws {
        let data = """
        {
          "id": "workspace01",
          "active": true,
          "info": {
            "title": "Imported",
            "description": "Shared workspace",
            "thumbnail": ""
          },
          "blocks": [],
          "notes": []
        }
        """.data(using: .utf8)!

        let groups = try ProjectStore.decodeGroups(from: data)

        #expect(groups.count == 1)
        #expect(groups[0].workspaces.count == 1)
        #expect(groups[0].workspaces[0].info.title == "Imported")
    }

    @Test func importsRealPALWorkspaceGraphWhenReferenceCheckoutExists() throws {
        let workspaceURL = URL(fileURLWithPath: "/private/tmp/pal-blocks-reference/data/workspaces.json")
        let blocksURL = URL(fileURLWithPath: "/private/tmp/pal-blocks-reference/blocks")
        guard FileManager.default.fileExists(atPath: workspaceURL.path) else { return }

        let data = try Data(contentsOf: workspaceURL)
        let groups = try ProjectStore.decodeGroups(from: data)
        let workspaceCount = groups.reduce(0) { $0 + $1.workspaces.count }
        let blockCount = groups.flatMap(\.workspaces).reduce(0) { $0 + $1.blocks.count }

        #expect(groups.count == 6)
        #expect(workspaceCount == 17)
        #expect(blockCount == 442)

        let library = try BlockParser().parseDirectory(blocksURL)
        let projectURL = workspaceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let store = ProjectStore(projectURL: projectURL, groups: groups)
        let firstWorkspaceID = try #require(store.workspaceReferences.first?.workspaceID)
        let document = try store.document(for: firstWorkspaceID, library: library)

        #expect(!document.blocks.isEmpty)
        #expect(!document.connections.isEmpty)
        #expect(document.blocks.contains { $0.blockFileName == "interaction_event" })
    }
}
