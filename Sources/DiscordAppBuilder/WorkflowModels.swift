import Foundation
import SwiftUI

enum AppAppearance: String, CaseIterable, Codable, Identifiable {
    static let storageKey = "DiscordAppBuilder.appearance"

    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

indirect enum JSONValue: Codable, Hashable, Sendable {
    case null
    case boolean(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .boolean(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    var displayString: String {
        switch self {
        case .null:
            return "null"
        case .boolean(let value):
            return value ? "true" : "false"
        case .integer(let value):
            return String(value)
        case .number(let value):
            return String(value)
        case .string(let value):
            return value
        case .array, .object:
            guard let data = try? JSONEncoder().encode(self) else { return "" }
            return String(decoding: data, as: UTF8.self)
        }
    }

    var wireIDs: [String] {
        switch self {
        case .string(let value):
            value.isEmpty ? [] : [value]
        case .array(let values):
            values.compactMap {
                guard case .string(let value) = $0, !value.isEmpty else { return nil }
                return value
            }
        default:
            []
        }
    }
}

enum BlockValueType: String, CaseIterable, Codable, Hashable, Sendable {
    case unspecified
    case undefined
    case null
    case object
    case boolean
    case number
    case text
    case list
    case date
    case action

    var color: Color {
        switch self {
        case .action: .green
        case .text: .purple
        case .number: .orange
        case .boolean: .pink
        case .object: .blue
        case .list: .yellow
        case .date: .indigo
        case .null, .undefined: .gray
        case .unspecified: .secondary
        }
    }
}

struct BlockPort: Identifiable, Codable, Hashable, Sendable {
    enum Direction: String, Codable, Sendable {
        case input
        case output
    }

    var id: String
    var name: String
    var description: String
    var types: [BlockValueType]
    var required: Bool
    var direction: Direction
    var allowsMultipleConnections: Bool

    init(
        id: String,
        name: String,
        description: String,
        types: [BlockValueType],
        required: Bool,
        direction: Direction,
        allowsMultipleConnections: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.types = types
        self.required = required
        self.direction = direction
        self.allowsMultipleConnections = allowsMultipleConnections
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case types
        case required
        case direction
        case allowsMultipleConnections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        types = try container.decode([BlockValueType].self, forKey: .types)
        required = try container.decode(Bool.self, forKey: .required)
        direction = try container.decode(Direction.self, forKey: .direction)
        allowsMultipleConnections = try container.decodeIfPresent(
            Bool.self,
            forKey: .allowsMultipleConnections
        ) ?? false
    }

    func accepts(_ other: BlockPort) -> Bool {
        guard direction != other.direction else { return false }
        if types.contains(.unspecified) || other.types.contains(.unspecified) {
            return true
        }
        return !Set(types).isDisjoint(with: Set(other.types))
    }

    func resolvedValueType(connectedTo other: BlockPort? = nil) -> BlockValueType {
        guard let other else {
            return types.first { $0 != .unspecified } ?? types.first ?? .unspecified
        }

        let ownConcreteTypes = types.filter { $0 != .unspecified }
        let otherConcreteTypes = other.types.filter { $0 != .unspecified }
        if let sharedType = ownConcreteTypes.first(where: otherConcreteTypes.contains) {
            return sharedType
        }
        if types.contains(.unspecified), let connectedType = otherConcreteTypes.first {
            return connectedType
        }
        if other.types.contains(.unspecified), let ownType = ownConcreteTypes.first {
            return ownType
        }
        return ownConcreteTypes.first ?? otherConcreteTypes.first ?? .unspecified
    }

    var color: Color {
        resolvedValueType().color
    }
}

struct BlockOption: Identifiable, Codable, Hashable, Sendable {
    enum OptionType: String, Codable, CaseIterable, Sendable {
        case select = "SELECT"
        case text = "TEXT"
        case color = "COLOR"
        case number = "NUMBER"
        case checkbox = "CHECKBOX"
        case multiselect = "MULTISELECT"
        case unknown = "UNKNOWN"
    }

    var id: String
    var name: String
    var description: String
    var type: OptionType
    var choices: [String: String]
    var choiceOrder: [String]? = nil
    var defaultValue: JSONValue? = nil
}

struct BlockDefinition: Identifiable, Codable, Hashable, Sendable {
    var id: String { sourceFile ?? name }
    var name: String
    var description: String
    var category: String
    var autoExecute: Bool
    var inputs: [BlockPort]
    var options: [BlockOption]
    var outputs: [BlockPort]
    var sourceFile: String?
}

struct WorkflowBlock: Identifiable, Codable, Hashable {
    static let minimumEditorWidth: CGFloat = 220
    static let minimumEditorHeight: CGFloat = 140

    var id = UUID()
    var runtimeBlockID: String? = nil
    var definition: BlockDefinition
    var position: CGPoint
    var optionValues: [String: JSONValue] = [:]
    var inputWireValues: [String: JSONValue] = [:]
    var blockFileName: String
    var color = ""
    var zIndex = 0
    var width: CGFloat = 300
    var height: CGFloat = 160
    var isLocked = false
    var isActive = true

    func displayedBlockID(workspaceID: String?) -> String? {
        guard let runtimeBlockID, !runtimeBlockID.isEmpty else { return nil }
        guard let workspaceID, !workspaceID.isEmpty else {
            return "#\(runtimeBlockID)"
        }
        let prefix = "\(workspaceID):"
        let suffix = runtimeBlockID.hasPrefix(prefix)
            ? String(runtimeBlockID.dropFirst(prefix.count))
            : runtimeBlockID
        return "#\(suffix)"
    }
}

struct WorkflowConnection: Identifiable, Codable, Hashable {
    var id = UUID()
    var wireID: String
    var fromBlockID: UUID
    var fromPortID: String
    var toBlockID: UUID
    var toPortID: String
}

struct WorkflowPortEndpoint: Hashable, Sendable {
    let blockID: UUID
    let portID: String
    let direction: BlockPort.Direction
}

struct WorkflowConnectionOccurrences: Sendable {
    let output: Int
    let input: Int
}

private struct WorkflowPortOccurrence: Hashable, Sendable {
    let endpoint: WorkflowPortEndpoint
    let occurrence: Int
}

struct WorkflowGraphIndex: Sendable {
    private let ports: [WorkflowPortEndpoint: BlockPort]
    private let connectionCounts: [WorkflowPortEndpoint: Int]
    private let storedInputCounts: [WorkflowPortEndpoint: Int]
    private let connectionOccurrences: [WorkflowConnection.ID: WorkflowConnectionOccurrences]
    private let connectionTypes: [WorkflowConnection.ID: BlockValueType]
    private let portTypes: [WorkflowPortOccurrence: BlockValueType]

    init(document: WorkflowDocument) {
        var indexedPorts: [WorkflowPortEndpoint: BlockPort] = [:]
        var indexedStoredInputCounts: [WorkflowPortEndpoint: Int] = [:]

        for block in document.blocks {
            for port in block.definition.inputs {
                let endpoint = WorkflowPortEndpoint(
                    blockID: block.id,
                    portID: port.id,
                    direction: .input
                )
                indexedPorts[endpoint] = port
                indexedStoredInputCounts[endpoint] = block.inputWireValues[port.id]?.wireIDs.count ?? 0
            }
            for port in block.definition.outputs {
                indexedPorts[
                    WorkflowPortEndpoint(
                        blockID: block.id,
                        portID: port.id,
                        direction: .output
                    )
                ] = port
            }
        }

        var indexedConnectionCounts: [WorkflowPortEndpoint: Int] = [:]
        var indexedOccurrences: [WorkflowConnection.ID: WorkflowConnectionOccurrences] = [:]
        var indexedConnectionTypes: [WorkflowConnection.ID: BlockValueType] = [:]
        var indexedPortTypes: [WorkflowPortOccurrence: BlockValueType] = [:]

        for connection in document.connections {
            let outputEndpoint = WorkflowPortEndpoint(
                blockID: connection.fromBlockID,
                portID: connection.fromPortID,
                direction: .output
            )
            let inputEndpoint = WorkflowPortEndpoint(
                blockID: connection.toBlockID,
                portID: connection.toPortID,
                direction: .input
            )
            let outputOccurrence = indexedPorts[outputEndpoint]?.allowsMultipleConnections == true
                ? indexedConnectionCounts[outputEndpoint, default: 0]
                : 0
            let inputOccurrence = indexedPorts[inputEndpoint]?.allowsMultipleConnections == true
                ? indexedConnectionCounts[inputEndpoint, default: 0]
                : 0

            indexedOccurrences[connection.id] = WorkflowConnectionOccurrences(
                output: outputOccurrence,
                input: inputOccurrence
            )
            indexedConnectionCounts[outputEndpoint, default: 0] += 1
            indexedConnectionCounts[inputEndpoint, default: 0] += 1

            let resolvedType = indexedPorts[outputEndpoint]?.resolvedValueType(
                connectedTo: indexedPorts[inputEndpoint]
            ) ?? indexedPorts[inputEndpoint]?.resolvedValueType() ?? .unspecified
            indexedConnectionTypes[connection.id] = resolvedType

            let outputKey = WorkflowPortOccurrence(
                endpoint: outputEndpoint,
                occurrence: outputOccurrence
            )
            let inputKey = WorkflowPortOccurrence(
                endpoint: inputEndpoint,
                occurrence: inputOccurrence
            )
            if indexedPortTypes[outputKey] == nil {
                indexedPortTypes[outputKey] = resolvedType
            }
            if indexedPortTypes[inputKey] == nil {
                indexedPortTypes[inputKey] = resolvedType
            }
        }

        ports = indexedPorts
        connectionCounts = indexedConnectionCounts
        storedInputCounts = indexedStoredInputCounts
        connectionOccurrences = indexedOccurrences
        connectionTypes = indexedConnectionTypes
        portTypes = indexedPortTypes
    }

    func port(for endpoint: WorkflowPortEndpoint) -> BlockPort? {
        ports[endpoint]
    }

    func connectionCount(for endpoint: WorkflowPortEndpoint) -> Int {
        connectionCounts[endpoint, default: 0]
    }

    func storedInputCount(for endpoint: WorkflowPortEndpoint) -> Int {
        storedInputCounts[endpoint, default: 0]
    }

    func occurrences(for connection: WorkflowConnection) -> WorkflowConnectionOccurrences {
        connectionOccurrences[connection.id]
            ?? WorkflowConnectionOccurrences(output: 0, input: 0)
    }

    func resolvedValueType(for connection: WorkflowConnection) -> BlockValueType {
        connectionTypes[connection.id] ?? .unspecified
    }

    func resolvedValueType(
        for endpoint: WorkflowPortEndpoint,
        occurrence: Int
    ) -> BlockValueType {
        portTypes[WorkflowPortOccurrence(endpoint: endpoint, occurrence: occurrence)]
            ?? ports[endpoint]?.resolvedValueType()
            ?? .unspecified
    }
}

struct WorkflowDocument: Codable, Hashable {
    var name = "Untitled Bot"
    var blocks: [WorkflowBlock] = []
    var connections: [WorkflowConnection] = []
}

struct WorkflowClipboardPayload: Codable {
    var projectPath: String?
    var blocks: [WorkflowBlock]
    var connections: [WorkflowConnection]
}

struct RecentProject: Identifiable, Hashable {
    var id: String { path }
    let path: String

    var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    var name: String {
        url.lastPathComponent
    }

    var initials: String {
        let words = name.split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? String(name.prefix(2)).uppercased() : String(letters).uppercased()
    }
}
