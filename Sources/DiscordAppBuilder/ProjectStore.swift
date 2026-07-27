import Foundation

struct WorkspaceGroupInfo: Codable, Hashable {
    var title: String
    var collapsed: Bool
}

struct WorkspaceInfo: Codable, Hashable {
    var title: String
    var description: String
    var thumbnail: String
}

struct StoredBlock: Codable, Hashable {
    var blockID: String? = nil
    var id: String? = nil
    var color: String
    var x: Double
    var y: Double
    var z: Int
    var width: Double
    var height: Double
    var lock: Bool
    var name: String
    var inputs: [String: JSONValue]
    var options: [String: JSONValue]
    var outputs: [String: JSONValue]
    var active: Bool

    private enum CodingKeys: String, CodingKey {
        case blockID = "block_id"
        case id
        case color
        case x
        case y
        case z
        case width
        case height
        case lock
        case name
        case inputs
        case options
        case outputs
        case active
    }
}

struct StoredNote: Codable, Hashable {
    var color: String
    var x: Double
    var y: Double
    var z: Int
    var width: Double
    var height: Double
    var lock: Bool
    var title: String
    var description: String
}

struct ProjectWorkspace: Identifiable, Codable, Hashable {
    var id: String
    var active: Bool
    var info: WorkspaceInfo
    var blocks: [StoredBlock]
    var notes: [StoredNote]
}

struct WorkspaceGroup: Identifiable, Codable, Hashable {
    var id: String
    var info: WorkspaceGroupInfo
    var workspaces: [ProjectWorkspace]
}

struct WorkspaceReference: Identifiable, Hashable {
    var id: String { "\(groupID)/\(workspaceID)" }
    let groupID: String
    let workspaceID: String
    let groupTitle: String
    let title: String
}

enum ProjectStoreError: Error, LocalizedError {
    case invalidProjectFolder
    case missingWorkspaceFile
    case invalidWorkspaceFile
    case workspaceNotFound
    case categoryNotFound
    case invalidBlockFilename
    case missingBlockFile(String)
    case blockFileAlreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .invalidProjectFolder:
            "The selected location is not a valid project folder."
        case .missingWorkspaceFile:
            "No data/workspaces.json file was found."
        case .invalidWorkspaceFile:
            "The workspace JSON is not in a supported format."
        case .workspaceNotFound:
            "The selected workspace could not be found."
        case .categoryNotFound:
            "The selected category could not be found."
        case .invalidBlockFilename:
            "Use a filename containing only letters, numbers, underscores, or hyphens."
        case .missingBlockFile(let filename):
            "The block file \(filename).js could not be found in the project's blocks folder."
        case .blockFileAlreadyExists(let filename):
            "A block file named \(filename).js already exists."
        }
    }
}

struct ProjectStore {
    static let workspaceFileName = "workspaces.json"

    private(set) var projectURL: URL
    var groups: [WorkspaceGroup]

    var workspaceReferences: [WorkspaceReference] {
        groups.flatMap { group in
            group.workspaces.map { workspace in
                WorkspaceReference(
                    groupID: group.id,
                    workspaceID: workspace.id,
                    groupTitle: group.info.title,
                    title: workspace.info.title
                )
            }
        }
    }

    static func createProject(at projectURL: URL) throws -> ProjectStore {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: projectURL.appending(path: "blocks", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: projectURL.appending(path: "data", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: projectURL.appending(path: "config", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        let workspace = ProjectWorkspace(
            id: ProjectIdentifier.make(),
            active: true,
            info: WorkspaceInfo(title: "Main Workspace", description: "", thumbnail: ""),
            blocks: [],
            notes: []
        )
        let group = WorkspaceGroup(
            id: ProjectIdentifier.make(),
            info: WorkspaceGroupInfo(title: "Workspaces", collapsed: false),
            workspaces: [workspace]
        )
        var store = ProjectStore(projectURL: projectURL, groups: [group])
        try store.writeScaffold()
        try store.save()
        return store
    }

    static func openProject(at projectURL: URL) throws -> ProjectStore {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw ProjectStoreError.invalidProjectFolder
        }

        let dataDirectory = projectURL.appending(path: "data", directoryHint: .isDirectory)
        let workspaceURL = dataDirectory.appending(path: workspaceFileName)
        guard FileManager.default.fileExists(atPath: workspaceURL.path) else {
            throw ProjectStoreError.missingWorkspaceFile
        }

        let data = try Data(contentsOf: workspaceURL)
        let groups = try decodeGroups(from: data)
        return ProjectStore(projectURL: projectURL, groups: groups)
    }

    static func decodeGroups(from data: Data) throws -> [WorkspaceGroup] {
        let decoder = JSONDecoder()
        if let groups = try? decoder.decode([WorkspaceGroup].self, from: data) {
            return groups
        }
        if let workspaces = try? decoder.decode([ProjectWorkspace].self, from: data) {
            return [
                WorkspaceGroup(
                    id: ProjectIdentifier.make(),
                    info: WorkspaceGroupInfo(title: "Imported Workspaces", collapsed: false),
                    workspaces: workspaces
                )
            ]
        }
        if let workspace = try? decoder.decode(ProjectWorkspace.self, from: data) {
            return [
                WorkspaceGroup(
                    id: ProjectIdentifier.make(),
                    info: WorkspaceGroupInfo(title: "Imported Workspaces", collapsed: false),
                    workspaces: [workspace]
                )
            ]
        }
        throw ProjectStoreError.invalidWorkspaceFile
    }

    mutating func save(document: WorkflowDocument? = nil, workspaceID: String? = nil) throws {
        if let document, let workspaceID {
            try update(document: document, workspaceID: workspaceID)
        }
        let data = try JSONEncoder.workspacePretty.encode(groups)
        let dataDirectory = projectURL.appending(path: "data", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try data.write(to: dataDirectory.appending(path: Self.workspaceFileName), options: .atomic)
    }

    mutating func importWorkspaces(from url: URL) throws {
        let data = try Data(contentsOf: url)
        groups = try Self.decodeGroups(from: data)
        try save()
    }

    func document(for workspaceID: String, library: [BlockDefinition]) throws -> WorkflowDocument {
        guard let workspace = groups.lazy.flatMap(\.workspaces).first(where: { $0.id == workspaceID }) else {
            throw ProjectStoreError.workspaceNotFound
        }

        let definitionsByFileName = Dictionary(
            library.compactMap { definition -> (String, BlockDefinition)? in
                guard let sourceFile = definition.sourceFile else { return nil }
                let fileName = URL(fileURLWithPath: sourceFile)
                    .deletingPathExtension()
                    .lastPathComponent
                return (fileName, definition)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let blocks: [WorkflowBlock] = workspace.blocks.enumerated().map { index, stored in
            let definition = definition(
                for: stored,
                definitionsByFileName: definitionsByFileName
            )
            let width = CGFloat(stored.width)
            let height = CGFloat(stored.height)
            return WorkflowBlock(
                runtimeBlockID: stored.blockID ?? stored.id ?? "\(workspace.id):\(index)",
                definition: definition,
                position: CGPoint(
                    x: CGFloat(stored.x) + width / 2,
                    y: CGFloat(stored.y) + height / 2
                ),
                optionValues: stored.options,
                inputWireValues: stored.inputs,
                blockFileName: stored.name,
                color: stored.color,
                zIndex: stored.z,
                width: width,
                height: height,
                isLocked: stored.lock,
                isActive: stored.active
            )
        }

        var outputSources: [String: (blockID: UUID, portID: String)] = [:]
        for blockIndex in blocks.indices {
            for (portID, value) in workspace.blocks[blockIndex].outputs {
                for wireID in value.wireIDs {
                    outputSources[wireID] = (blocks[blockIndex].id, portID)
                }
            }
        }

        var connections: [WorkflowConnection] = []
        for block in blocks {
            for (portID, value) in block.inputWireValues {
                for wireID in value.wireIDs {
                    guard let source = outputSources[wireID] else { continue }
                    connections.append(
                        WorkflowConnection(
                            wireID: wireID,
                            fromBlockID: source.blockID,
                            fromPortID: source.portID,
                            toBlockID: block.id,
                            toPortID: portID
                        )
                    )
                }
            }
        }

        return WorkflowDocument(name: workspace.info.title, blocks: blocks, connections: connections)
    }

    mutating func addWorkspace(named title: String, to groupID: String? = nil) -> WorkspaceReference {
        if groups.isEmpty {
            groups.append(
                WorkspaceGroup(
                    id: ProjectIdentifier.make(),
                    info: WorkspaceGroupInfo(title: "Workspaces", collapsed: false),
                    workspaces: []
                )
            )
        }
        let groupIndex = groupID.flatMap { id in groups.firstIndex(where: { $0.id == id }) } ?? 0
        let workspace = ProjectWorkspace(
            id: ProjectIdentifier.make(),
            active: true,
            info: WorkspaceInfo(title: title, description: "", thumbnail: ""),
            blocks: [],
            notes: []
        )
        groups[groupIndex].workspaces.append(workspace)
        return WorkspaceReference(
            groupID: groups[groupIndex].id,
            workspaceID: workspace.id,
            groupTitle: groups[groupIndex].info.title,
            title: title
        )
    }

    @discardableResult
    mutating func addCategory(named title: String) -> WorkspaceGroup {
        let group = WorkspaceGroup(
            id: ProjectIdentifier.make(),
            info: WorkspaceGroupInfo(title: title, collapsed: false),
            workspaces: []
        )
        groups.append(group)
        return group
    }

    mutating func setCategory(_ groupID: String, collapsed: Bool) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].info.collapsed = collapsed
    }

    mutating func renameCategory(_ groupID: String, to title: String) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].info.title = title
    }

    mutating func renameWorkspace(_ workspaceID: String, to title: String) {
        for groupIndex in groups.indices {
            guard let workspaceIndex = groups[groupIndex].workspaces.firstIndex(where: { $0.id == workspaceID }) else {
                continue
            }
            groups[groupIndex].workspaces[workspaceIndex].info.title = title
            return
        }
    }

    func workspace(withID workspaceID: String) -> ProjectWorkspace? {
        groups.lazy
            .flatMap(\.workspaces)
            .first(where: { $0.id == workspaceID })
    }

    func groupID(containing workspaceID: String) -> String? {
        groups.first(where: {
            $0.workspaces.contains(where: { $0.id == workspaceID })
        })?.id
    }

    mutating func moveWorkspace(_ workspaceID: String, to groupID: String) throws {
        guard let destinationIndex = groups.firstIndex(where: { $0.id == groupID }) else {
            throw ProjectStoreError.categoryNotFound
        }
        guard let sourceIndex = groups.firstIndex(where: { group in
            group.workspaces.contains(where: { $0.id == workspaceID })
        }), let workspaceIndex = groups[sourceIndex].workspaces.firstIndex(where: {
            $0.id == workspaceID
        }) else {
            throw ProjectStoreError.workspaceNotFound
        }
        guard sourceIndex != destinationIndex else { return }

        let workspace = groups[sourceIndex].workspaces.remove(at: workspaceIndex)
        groups[destinationIndex].workspaces.append(workspace)
    }

    mutating func setWorkspace(_ workspaceID: String, active: Bool) throws {
        for groupIndex in groups.indices {
            guard let workspaceIndex = groups[groupIndex].workspaces.firstIndex(where: {
                $0.id == workspaceID
            }) else { continue }
            groups[groupIndex].workspaces[workspaceIndex].active = active
            return
        }
        throw ProjectStoreError.workspaceNotFound
    }

    @discardableResult
    mutating func deleteWorkspace(_ workspaceID: String) throws -> ProjectWorkspace {
        for groupIndex in groups.indices {
            guard let workspaceIndex = groups[groupIndex].workspaces.firstIndex(where: {
                $0.id == workspaceID
            }) else { continue }
            return groups[groupIndex].workspaces.remove(at: workspaceIndex)
        }
        throw ProjectStoreError.workspaceNotFound
    }

    @discardableResult
    mutating func insertWorkspaceCopy(
        _ source: ProjectWorkspace,
        into groupID: String
    ) throws -> WorkspaceReference {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupID }) else {
            throw ProjectStoreError.categoryNotFound
        }

        let workspaceID = ProjectIdentifier.make()
        var copy = source
        copy.id = workspaceID
        copy.info.title = availableCopyTitle(
            for: source.info.title,
            in: groups[groupIndex]
        )
        for index in copy.blocks.indices {
            let existingID = copy.blocks[index].blockID ?? copy.blocks[index].id
            let suffix: String
            if let existingID,
               let separator = existingID.firstIndex(of: ":") {
                suffix = String(existingID[existingID.index(after: separator)...])
            } else {
                suffix = String(index)
            }
            let copiedID = "\(workspaceID):\(suffix)"
            copy.blocks[index].blockID = copiedID
            if copy.blocks[index].id != nil {
                copy.blocks[index].id = copiedID
            }
        }
        groups[groupIndex].workspaces.append(copy)

        return WorkspaceReference(
            groupID: groupID,
            workspaceID: workspaceID,
            groupTitle: groups[groupIndex].info.title,
            title: copy.info.title
        )
    }

    private func availableCopyTitle(
        for title: String,
        in group: WorkspaceGroup
    ) -> String {
        let existingTitles = Set(group.workspaces.map { $0.info.title.lowercased() })
        let base = "\(title) Copy"
        if !existingTitles.contains(base.lowercased()) {
            return base
        }

        var sequence = 2
        while existingTitles.contains("\(base) \(sequence)".lowercased()) {
            sequence += 1
        }
        return "\(base) \(sequence)"
    }

    @discardableResult
    mutating func renameBlockFile(from oldFilename: String, to newFilename: String) throws -> String {
        let oldName = try normalizedBlockFilename(oldFilename)
        let newName = try normalizedBlockFilename(newFilename)
        guard oldName != newName else { return newName }

        let blocksURL = projectURL.appending(path: "blocks", directoryHint: .isDirectory)
        let sourceURL = blocksURL.appending(path: "\(oldName).js")
        let destinationURL = blocksURL.appending(path: "\(newName).js")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            throw ProjectStoreError.missingBlockFile(oldName)
        }
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw ProjectStoreError.blockFileAlreadyExists(newName)
        }

        let originalGroups = groups
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        for groupIndex in groups.indices {
            for workspaceIndex in groups[groupIndex].workspaces.indices {
                for blockIndex in groups[groupIndex].workspaces[workspaceIndex].blocks.indices
                where groups[groupIndex].workspaces[workspaceIndex].blocks[blockIndex].name == oldName {
                    groups[groupIndex].workspaces[workspaceIndex].blocks[blockIndex].name = newName
                }
            }
        }

        do {
            try save()
        } catch {
            groups = originalGroups
            try? FileManager.default.moveItem(at: destinationURL, to: sourceURL)
            throw error
        }
        return newName
    }

    private func normalizedBlockFilename(_ filename: String) throws -> String {
        var value = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasSuffix(".js") {
            value.removeLast(3)
        }
        guard !value.isEmpty,
              value.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
                options: .regularExpression
              ) != nil
        else {
            throw ProjectStoreError.invalidBlockFilename
        }
        return value
    }

    mutating func update(document: WorkflowDocument, workspaceID: String) throws {
        guard let groupIndex = groups.firstIndex(where: { group in
            group.workspaces.contains(where: { $0.id == workspaceID })
        }), let workspaceIndex = groups[groupIndex].workspaces.firstIndex(where: { $0.id == workspaceID })
        else {
            throw ProjectStoreError.workspaceNotFound
        }

        var storedBlocks = document.blocks.map { block in
            var outputs: [String: JSONValue] = [:]
            for port in block.definition.outputs {
                outputs[port.id] = .array([])
            }
            return StoredBlock(
                blockID: block.runtimeBlockID,
                color: block.color,
                x: Double(block.position.x - block.width / 2),
                y: Double(block.position.y - block.height / 2),
                z: block.zIndex,
                width: Double(block.width),
                height: Double(block.height),
                lock: block.isLocked,
                name: block.blockFileName,
                inputs: block.inputWireValues,
                options: block.optionValues,
                outputs: outputs,
                active: block.isActive
            )
        }

        let blockIndexes = Dictionary(uniqueKeysWithValues: document.blocks.enumerated().map { ($0.element.id, $0.offset) })
        for connection in document.connections {
            guard let fromIndex = blockIndexes[connection.fromBlockID] else { continue }
            let existing = storedBlocks[fromIndex].outputs[connection.fromPortID]?.wireIDs ?? []
            if !existing.contains(connection.wireID) {
                storedBlocks[fromIndex].outputs[connection.fromPortID] = .array(
                    (existing + [connection.wireID]).map(JSONValue.string)
                )
            }
        }

        groups[groupIndex].workspaces[workspaceIndex].info.title = document.name
        groups[groupIndex].workspaces[workspaceIndex].blocks = storedBlocks
    }

    private func definition(
        for stored: StoredBlock,
        definitionsByFileName: [String: BlockDefinition]
    ) -> BlockDefinition {
        if let definition = definitionsByFileName[stored.name] {
            let sourceURL = projectURL
                .appending(path: "blocks", directoryHint: .isDirectory)
                .appending(path: definition.sourceFile ?? "\(stored.name).js")
            return BlockParser().configuredDefinition(
                from: definition,
                at: sourceURL,
                optionValues: stored.options
            )
        }

        let inputs = stored.inputs.keys.sorted().map {
            BlockPort(
                id: $0,
                name: $0,
                description: "Imported input",
                types: [.unspecified],
                required: false,
                direction: .input
            )
        }
        let outputs = stored.outputs.keys.sorted().map {
            BlockPort(
                id: $0,
                name: $0,
                description: "Imported output",
                types: [.unspecified],
                required: false,
                direction: .output
            )
        }
        let options = stored.options.keys.sorted().map {
            BlockOption(
                id: $0,
                name: $0,
                description: "Imported option",
                type: .text,
                choices: [:]
            )
        }
        return BlockDefinition(
            name: stored.name,
            description: "The block file is not currently available in this project's blocks folder.",
            category: "Missing Blocks",
            autoExecute: false,
            inputs: inputs,
            options: options,
            outputs: outputs,
            sourceFile: "\(stored.name).js"
        )
    }

    @discardableResult
    func updateBotRuntime() throws -> URL? {
        let fileManager = FileManager.default
        let botURL = projectURL.appending(path: "bot.js")
        var backupURL: URL?

        if fileManager.fileExists(atPath: botURL.path) {
            let backupDirectory = projectURL.appending(path: "backups", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let stem = "bot-\(formatter.string(from: Date()))"
            var candidate = backupDirectory.appending(path: "\(stem).js")
            var suffix = 2
            while fileManager.fileExists(atPath: candidate.path) {
                candidate = backupDirectory.appending(path: "\(stem)-\(suffix).js")
                suffix += 1
            }
            try fileManager.copyItem(at: botURL, to: candidate)
            backupURL = candidate
        }

        try Data(ProjectTemplates.botRuntime.utf8).write(to: botURL, options: .atomic)

        let supportFiles: [(String, String)] = [
            ("logger.js", ProjectTemplates.logger),
            ("token.js", ProjectTemplates.tokenReader)
        ]
        for (filename, contents) in supportFiles {
            let url = projectURL.appending(path: filename)
            if !fileManager.fileExists(atPath: url.path) {
                try Data(contents.utf8).write(to: url, options: .atomic)
            }
        }

        let dataDirectory = projectURL.appending(path: "data", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let tokenURL = dataDirectory.appending(path: "token.txt")
        if !fileManager.fileExists(atPath: tokenURL.path) {
            try Data().write(to: tokenURL, options: .atomic)
        }
        let configURL = dataDirectory.appending(path: "config.json")
        if fileManager.fileExists(atPath: configURL.path) {
            let existingConfig = try Data(contentsOf: configURL)
            try normalizedConfigData(existingConfig).write(to: configURL, options: .atomic)
        } else {
            try migratedConfigData(from: dataDirectory.appending(path: "data.json"))
                .write(to: configURL, options: .atomic)
        }

        let rootConfigDirectory = projectURL.appending(
            path: "config",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: rootConfigDirectory,
            withIntermediateDirectories: true
        )
        for filename in ["server.txt", "log.txt"] {
            let url = rootConfigDirectory.appending(path: filename)
            if !fileManager.fileExists(atPath: url.path) {
                try Data().write(to: url, options: .atomic)
            }
        }
        return backupURL
    }

    private func migratedConfigData(from dataURL: URL) -> Data {
        let fallback = Data(
            ProjectTemplates.configJSON(applicationName: projectURL.lastPathComponent).utf8
        )
        guard let data = try? Data(contentsOf: dataURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let legacy = root[["d", "b", "b"].joined()] as? [String: Any]
        else {
            return fallback
        }

        let prefixes = legacy["prefixes"] as? [String: Any] ?? [:]
        let defaultPrefix = prefixes["main"] as? String ?? "!"
        let serverPrefixes = prefixes["servers"] as? [String: Any] ?? [:]
        let owners = legacy["owners"] as? [String] ?? []
        let config: [String: Any] = [
            "application": [
                "name": projectURL.lastPathComponent,
                "version": "1.0.0"
            ],
            "commands": [
                "defaultPrefix": defaultPrefix,
                "serverPrefixes": serverPrefixes
            ],
            "owners": owners
        ]
        return (try? JSONSerialization.data(
            withJSONObject: config,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )) ?? fallback
    }

    private func normalizedConfigData(_ data: Data) -> Data {
        let fallback = Data(
            ProjectTemplates.configJSON(applicationName: projectURL.lastPathComponent).utf8
        )
        guard var config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fallback
        }

        var application = config["application"] as? [String: Any] ?? [:]
        if (application["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ?? true {
            application["name"] = projectURL.lastPathComponent
        }
        if (application["version"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            application["version"] = "1.0.0"
        }
        config["application"] = application

        return (try? JSONSerialization.data(
            withJSONObject: config,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )) ?? fallback
    }

    private func writeScaffold() throws {
        let files: [(String, String)] = [
            ("package.json", ProjectTemplates.packageJSON),
            ("bot.js", ProjectTemplates.botRuntime),
            ("sharding.js", ProjectTemplates.sharding),
            ("logger.js", ProjectTemplates.logger),
            ("token.js", ProjectTemplates.tokenReader),
            ("data/data.json", ProjectTemplates.dataJSON),
            (
                "data/config.json",
                ProjectTemplates.configJSON(applicationName: projectURL.lastPathComponent)
            ),
            ("data/token.txt", ""),
            ("data/INTENTS.txt", ProjectTemplates.intents),
            ("config/server.txt", ""),
            ("config/log.txt", ""),
            ("blocks/bot_initialization_event.js", ProjectTemplates.initializationBlock),
            ("blocks/text.js", ProjectTemplates.textBlock),
            ("blocks/console_log.js", ProjectTemplates.consoleLogBlock)
        ]
        for (relativePath, contents) in files {
            let url = projectURL.appending(path: relativePath)
            try Data(contents.utf8).write(to: url, options: .atomic)
        }
    }
}

enum ProjectIdentifier {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")

    static func make(length: Int = 10) -> String {
        String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}

extension JSONEncoder {
    static var workspacePretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
