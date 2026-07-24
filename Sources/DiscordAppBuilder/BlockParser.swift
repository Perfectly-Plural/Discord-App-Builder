import Foundation
import JavaScriptCore

enum BlockParserError: Error, LocalizedError {
    case unreadableFile(URL)
    case missingModuleExport(URL)
    case missingName(URL)

    var errorDescription: String? {
        switch self {
        case .unreadableFile(let url):
            "Could not read \(url.lastPathComponent)."
        case .missingModuleExport(let url):
            "\(url.lastPathComponent) does not look like a compatible CommonJS block."
        case .missingName(let url):
            "\(url.lastPathComponent) is missing a block name."
        }
    }
}

private struct EvaluatedMetadata: Decodable {
    var inputs: [EvaluatedPort]
    var options: [EvaluatedOption]
    var outputs: [EvaluatedPort]
}

private struct EvaluatedPort: Decodable {
    var id: String
    var name: String?
    var description: String?
    var types: [String] = []
    var required: Bool?
    var multiInput: Bool?
    var multiOutput: Bool?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case types
        case required
        case multiInput
        case multiOutput
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        types = try container.decodeIfPresent([String].self, forKey: .types) ?? []
        required = try container.decodeIfPresent(Bool.self, forKey: .required)
        multiInput = try container.decodeIfPresent(Bool.self, forKey: .multiInput)
        multiOutput = try container.decodeIfPresent(Bool.self, forKey: .multiOutput)
    }
}

private struct EvaluatedOption: Decodable {
    var id: String
    var name: String?
    var description: String?
    var type: String?
    var options: JSONValue?
    var defaultValue: JSONValue?
}

private final class CachedBlockDefinition: NSObject {
    let definition: BlockDefinition
    let usesDynamicMetadata: Bool

    init(definition: BlockDefinition, usesDynamicMetadata: Bool) {
        self.definition = definition
        self.usesDynamicMetadata = usesDynamicMetadata
    }
}

private enum BlockDefinitionCache {
    nonisolated(unsafe) static let base = NSCache<NSString, CachedBlockDefinition>()
    nonisolated(unsafe) static let configured = NSCache<NSString, CachedBlockDefinition>()

    static func configure() {
        base.countLimit = 512
        configured.countLimit = 1_024
    }
}

struct BlockParser {
    func parseDirectory(_ url: URL) throws -> [BlockDefinition] {
        let files = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        )
        return files
            .filter { $0.pathExtension.lowercased() == "js" }
            .compactMap { try? parseFile($0) }
            .sorted { lhs, rhs in
                lhs.category == rhs.category
                    ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    : lhs.category.localizedCaseInsensitiveCompare(rhs.category) == .orderedAscending
            }
    }

    func parseFile(
        _ url: URL,
        optionValues: [String: JSONValue] = [:]
    ) throws -> BlockDefinition {
        BlockDefinitionCache.configure()
        let baseCacheKey = fileRevisionKey(for: url)
        if let cached = BlockDefinitionCache.base.object(
            forKey: baseCacheKey as NSString
        ), !cached.usesDynamicMetadata {
            return cached.definition
        }

        let configuredCacheKey = "\(baseCacheKey)|\(optionsCacheKey(optionValues))"
        if let cached = BlockDefinitionCache.configured.object(
            forKey: configuredCacheKey as NSString
        ) {
            return cached.definition
        }

        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw BlockParserError.unreadableFile(url)
        }
        guard let body = objectBody(after: "module.exports", in: source) else {
            throw BlockParserError.missingModuleExport(url)
        }
        guard let name = stringValue(for: "name", in: body), !name.isEmpty else {
            throw BlockParserError.missingName(url)
        }
        let dynamicPattern = #"(?m)\b(?:inputs|options|outputs)\s*\([^)]*\)\s*\{"#
        let usesDynamicMetadata = source.range(
            of: dynamicPattern,
            options: .regularExpression
        ) != nil
        let evaluated = usesDynamicMetadata
            ? dynamicMetadata(in: source, optionValues: optionValues)
            : nil

        let definition = BlockDefinition(
            name: name,
            description: stringValue(for: "description", in: body) ?? "",
            category: stringValue(for: "category", in: body) ?? "Uncategorized",
            autoExecute: boolValue(for: "auto_execute", in: body) ?? false,
            inputs: evaluated.map {
                ports(from: $0.inputs, direction: .input)
            } ?? ports(for: "inputs", direction: .input, in: body),
            options: evaluated.map {
                options(from: $0.options)
            } ?? options(in: body),
            outputs: evaluated.map {
                ports(from: $0.outputs, direction: .output)
            } ?? ports(for: "outputs", direction: .output, in: body),
            sourceFile: url.lastPathComponent
        )
        let cached = CachedBlockDefinition(
            definition: definition,
            usesDynamicMetadata: usesDynamicMetadata
        )
        BlockDefinitionCache.base.setObject(cached, forKey: baseCacheKey as NSString)
        BlockDefinitionCache.configured.setObject(
            cached,
            forKey: configuredCacheKey as NSString
        )
        return definition
    }

    private func fileRevisionKey(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let modified = (attributes?[.modificationDate] as? Date)?
            .timeIntervalSinceReferenceDate ?? -1
        let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        return "\(path)|\(modified)|\(size)"
    }

    private func optionsCacheKey(_ values: [String: JSONValue]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(values) else { return "" }
        return data.base64EncodedString()
    }

    private func ports(
        from values: [EvaluatedPort],
        direction: BlockPort.Direction
    ) -> [BlockPort] {
        values.map { value in
            let types = value.types
                .compactMap { BlockValueType(rawValue: $0.lowercased()) }
            return BlockPort(
                id: value.id,
                name: value.name ?? value.id,
                description: value.description ?? "",
                types: types.isEmpty ? [.unspecified] : types,
                required: value.required ?? false,
                direction: direction,
                allowsMultipleConnections: direction == .input
                    ? value.multiInput ?? false
                    : value.multiOutput ?? false
            )
        }
    }

    private func options(from values: [EvaluatedOption]) -> [BlockOption] {
        values.map { value in
            let choices = optionChoices(from: value.options)
            return BlockOption(
                id: value.id,
                name: value.name ?? value.id,
                description: value.description ?? "",
                type: BlockOption.OptionType(
                    rawValue: value.type?.uppercased() ?? "UNKNOWN"
                ) ?? .unknown,
                choices: choices.values,
                choiceOrder: choices.order,
                defaultValue: value.defaultValue
            )
        }
    }

    private func optionChoices(
        from value: JSONValue?
    ) -> (values: [String: String], order: [String]) {
        var values: [String: String] = [:]
        var order: [String] = []

        func add(id: String, name: String) {
            guard values[id] == nil else { return }
            values[id] = name
            order.append(id)
        }

        func visit(_ value: JSONValue) {
            switch value {
            case .array(let items):
                for item in items {
                    guard case .object(let object) = item else { continue }
                    if object["type"]?.displayString.uppercased() == "GROUP",
                       let nested = object["options"] {
                        visit(nested)
                    } else if let id = object["id"]?.displayString, !id.isEmpty {
                        add(id: id, name: object["name"]?.displayString ?? id)
                    }
                }
            case .object(let object):
                for key in object.keys.sorted() {
                    guard let name = object[key]?.displayString else { continue }
                    add(id: key, name: name)
                }
            default:
                break
            }
        }

        if let value {
            visit(value)
        }
        return (values, order)
    }

    private func dynamicMetadata(
        in source: String,
        optionValues: [String: JSONValue]
    ) -> EvaluatedMetadata? {
        guard let context = JSContext() else { return nil }

        context.evaluateScript(
            """
            var module = { exports: {} };
            var exports = module.exports;
            var require = function() { return {}; };
            """
        )
        context.evaluateScript(source)
        guard context.exception == nil,
              let invocationData = try? JSONEncoder().encode(["options": optionValues]),
              let invocation = String(data: invocationData, encoding: .utf8)
        else {
            return nil
        }

        let result = context.evaluateScript(
            """
            (() => {
              const data = \(invocation);
              const resolve = key => {
                const value = module.exports[key];
                return typeof value === "function" ? value(data) : (value || []);
              };
              return JSON.stringify({
                inputs: resolve("inputs"),
                options: resolve("options"),
                outputs: resolve("outputs")
              });
            })()
            """
        )
        guard context.exception == nil,
              let json = result?.toString(),
              let data = json.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(EvaluatedMetadata.self, from: data)
    }

    private func ports(for key: String, direction: BlockPort.Direction, in source: String) -> [BlockPort] {
        arrayItems(for: key, in: source).compactMap { item in
            guard let id = stringValue(for: "id", in: item) else { return nil }
            let types = stringArrayValue(for: "types", in: item)
                .compactMap { BlockValueType(rawValue: $0.lowercased()) }
            return BlockPort(
                id: id,
                name: stringValue(for: "name", in: item) ?? id,
                description: stringValue(for: "description", in: item) ?? "",
                types: types.isEmpty ? [.unspecified] : types,
                required: boolValue(for: "required", in: item) ?? false,
                direction: direction,
                allowsMultipleConnections: boolValue(
                    for: direction == .input ? "multiInput" : "multiOutput",
                    in: item
                ) ?? false
            )
        }
    }

    private func options(in source: String) -> [BlockOption] {
        arrayItems(for: "options", in: source).compactMap { item in
            guard let id = stringValue(for: "id", in: item) else { return nil }
            let rawType = stringValue(for: "type", in: item)?.uppercased() ?? "UNKNOWN"
            return BlockOption(
                id: id,
                name: stringValue(for: "name", in: item) ?? id,
                description: stringValue(for: "description", in: item) ?? "",
                type: BlockOption.OptionType(rawValue: rawType) ?? .unknown,
                choices: objectStringMap(for: "options", in: item)
            )
        }
    }

    private func stringValue(for key: String, in source: String) -> String? {
        guard let valueStart = propertyValueStart(for: key, in: source),
              valueStart < source.endIndex
        else { return nil }
        let delimiter = source[valueStart]
        guard delimiter == "\"" || delimiter == "'" else { return nil }

        var index = source.index(after: valueStart)
        var escaped = false
        var value = ""
        while index < source.endIndex {
            let char = source[index]
            if escaped {
                value.append("\\")
                value.append(char)
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if char == delimiter {
                return unescape(value)
            } else {
                value.append(char)
            }
            index = source.index(after: index)
        }
        return nil
    }

    private func boolValue(for key: String, in source: String) -> Bool? {
        guard let valueStart = propertyValueStart(for: key, in: source) else { return nil }
        let tail = source[valueStart...]
        if tail.hasPrefix("true") { return true }
        if tail.hasPrefix("false") { return false }
        return nil
    }

    private func stringArrayValue(for key: String, in source: String) -> [String] {
        guard let array = bracketedValue(for: key, opening: "[", closing: "]", in: source) else {
            return []
        }
        let regex = try? NSRegularExpression(pattern: #"["']([^"']+)["']"#)
        let range = NSRange(array.startIndex..<array.endIndex, in: array)
        return regex?.matches(in: array, range: range).compactMap {
            Range($0.range(at: 1), in: array).map { String(array[$0]) }
        } ?? []
    }

    private func objectStringMap(for key: String, in source: String) -> [String: String] {
        guard let object = bracketedValue(for: key, opening: "{", closing: "}", in: source) else {
            return [:]
        }
        let regex = try? NSRegularExpression(
            pattern: #"(?m)(?:"([^"]+)"|'([^']+)'|([A-Za-z0-9_]+))\s*:\s*(?:"([^"]*)"|'([^']*)')"#
        )
        let range = NSRange(object.startIndex..<object.endIndex, in: object)
        var result: [String: String] = [:]
        regex?.matches(in: object, range: range).forEach { match in
            let key = firstCapturedString(match, indexes: [1, 2, 3], in: object)
            let value = firstCapturedString(match, indexes: [4, 5], in: object)
            if let key, let value {
                result[key] = value
            }
        }
        return result
    }

    private func arrayItems(for key: String, in source: String) -> [String] {
        guard let array = bracketedValue(for: key, opening: "[", closing: "]", in: source) else {
            return []
        }
        return topLevelObjects(in: array)
    }

    private func objectBody(after marker: String, in source: String) -> String? {
        guard let markerRange = source.range(of: marker),
              let equalsRange = source[markerRange.upperBound...].range(of: "="),
              let openBrace = source[equalsRange.upperBound...].firstIndex(of: "{")
        else { return nil }
        return balancedSubstring(from: openBrace, opening: "{", closing: "}", in: source)
    }

    private func bracketedValue(
        for key: String,
        opening: Character,
        closing: Character,
        in source: String
    ) -> String? {
        guard let valueStart = propertyValueStart(for: key, in: source),
              let openIndex = source[valueStart...].firstIndex(of: opening)
        else { return nil }
        return balancedSubstring(from: openIndex, opening: opening, closing: closing, in: source)
    }

    private func propertyValueStart(for key: String, in source: String) -> String.Index? {
        let candidates = ["\"\(key)\"", "'\(key)'", key]
        var earliest: String.Index?
        for candidate in candidates {
            var searchStart = source.startIndex
            while let keyRange = source.range(of: candidate, range: searchStart..<source.endIndex) {
                let before = keyRange.lowerBound == source.startIndex ? nil : source[source.index(before: keyRange.lowerBound)]
                let after = keyRange.upperBound == source.endIndex ? nil : source[keyRange.upperBound]
                let beforeOK = before == nil || before == "{" || before == "," || before?.isWhitespace == true
                let afterOK = after == nil || after == ":" || after?.isWhitespace == true
                if beforeOK && afterOK,
                   let colon = source[keyRange.upperBound...].firstIndex(of: ":") {
                    var valueStart = source.index(after: colon)
                    while valueStart < source.endIndex, source[valueStart].isWhitespace {
                        valueStart = source.index(after: valueStart)
                    }
                    if earliest == nil || valueStart < earliest! {
                        earliest = valueStart
                    }
                    break
                }
                searchStart = keyRange.upperBound
            }
        }
        return earliest
    }

    private func balancedSubstring(
        from openIndex: String.Index,
        opening: Character,
        closing: Character,
        in source: String
    ) -> String? {
        var depth = 0
        var inString: Character?
        var escaped = false
        var index = openIndex

        while index < source.endIndex {
            let char = source[index]
            defer { index = source.index(after: index) }

            if let delimiter = inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == delimiter {
                    inString = nil
                }
                continue
            }

            if char == "\"" || char == "'" || char == "`" {
                inString = char
            } else if char == opening {
                depth += 1
            } else if char == closing {
                depth -= 1
                if depth == 0 {
                    return String(source[openIndex...index])
                }
            }
        }
        return nil
    }

    private func topLevelObjects(in source: String) -> [String] {
        var objects: [String] = []
        var index = source.startIndex
        while index < source.endIndex {
            guard let open = source[index...].firstIndex(of: "{") else { break }
            guard let object = balancedSubstring(from: open, opening: "{", closing: "}", in: source) else { break }
            objects.append(object)
            index = source.index(open, offsetBy: object.count, limitedBy: source.endIndex) ?? source.endIndex
        }
        return objects
    }

    private func firstCapturedString(
        _ match: NSTextCheckingResult,
        indexes: [Int],
        in source: String
    ) -> String? {
        for index in indexes {
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: source)
            else { continue }
            return String(source[range])
        }
        return nil
    }

    private func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\""#, with: #"""#)
            .replacingOccurrences(of: #"\'"#, with: "'")
            .replacingOccurrences(of: #"\n"#, with: "\n")
    }
}
