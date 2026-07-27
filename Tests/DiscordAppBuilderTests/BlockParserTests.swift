import Foundation
import Testing
@testable import DiscordAppBuilder

struct BlockParserTests {
    @Test func parsesPALStyleBlockMetadata() throws {
        let source = """
        module.exports = {
            name: "Send Message",
            description: "Sends a message.",
            category: "Message Stuff",
            inputs: [
                { "id": "action", "name": "Action", "types": ["action"] },
                { "id": "text", "name": "Text", "types": ["text", "unspecified"], "required": true, "multiInput": true }
            ],
            options: [
                { "id": "silent", "name": "Silent Message", "type": "SELECT", "options": { undefined: "False", "true": "True" } }
            ],
            outputs: [
                { "id": "action", "name": "Action", "types": ["action"] }
            ],
            code(cache) {}
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "send_message_test.js")
        try source.write(to: url, atomically: true, encoding: .utf8)

        let block = try BlockParser().parseFile(url)

        #expect(block.name == "Send Message")
        #expect(block.category == "Message Stuff")
        #expect(block.inputs.count == 2)
        #expect(block.inputs[1].required)
        #expect(block.inputs[1].allowsMultipleConnections)
        #expect(block.inputs[1].types == [.text, .unspecified])
        #expect(block.options.first?.choices["true"] == "True")
        #expect(block.outputs.first?.types == [.action])
    }

    @Test func acceptsCompatibleTypes() {
        let output = BlockPort(id: "text", name: "Text", description: "", types: [.text], required: false, direction: .output)
        let input = BlockPort(id: "value", name: "Value", description: "", types: [.text, .number], required: false, direction: .input)
        let objectInput = BlockPort(id: "object", name: "Object", description: "", types: [.object], required: false, direction: .input)

        #expect(input.accepts(output))
        #expect(!objectInput.accepts(output))
    }

    @Test func unspecifiedActsAsWildcard() {
        let output = BlockPort(id: "value", name: "Value", description: "", types: [.unspecified], required: false, direction: .output)
        let input = BlockPort(id: "object", name: "Object", description: "", types: [.object], required: false, direction: .input)

        #expect(input.accepts(output))
    }

    @Test func importsRealPALBlocksWhenReferenceCheckoutExists() throws {
        let url = URL(fileURLWithPath: "/private/tmp/pal-blocks-reference/blocks")
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let blocks = try BlockParser().parseDirectory(url)

        #expect(blocks.count > 100)
        #expect(blocks.contains { $0.name == "Send Message" })
        #expect(blocks.contains { $0.autoExecute })
        let betterSendMessage = try #require(
            blocks.first { $0.sourceFile == "better_send_message.js" }
        )
        #expect(
            betterSendMessage.inputs.first { $0.id == "text" }?
                .allowsMultipleConnections == true
        )
        #expect(
            betterSendMessage.inputs.first { $0.id == "channel" }?
                .allowsMultipleConnections == false
        )
    }

    @Test func parsesDisplayNamesContainingParentheses() throws {
        let url = URL(
            fileURLWithPath: "/Volumes/Data/ONT/ValkyriaBot/blocks/merge_texts_advanced.js"
        )
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let block = try BlockParser().parseFile(url)
        let directory = url.deletingLastPathComponent()
        let library = try BlockParser().parseDirectory(directory)
        let sourceFiles = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter {
            guard $0.pathExtension.lowercased() == "js",
                  let attributes = try? FileManager.default.attributesOfItem(
                      atPath: $0.path
                  ),
                  let size = attributes[.size] as? NSNumber
            else { return false }
            return size.intValue > 0
        }
        .map(\.lastPathComponent)

        #expect(block.name == "Merge Texts (Advanced)")
        #expect(block.sourceFile == "merge_texts_advanced.js")
        #expect(library.contains { $0.sourceFile == "merge_texts_advanced.js" })
        let parsedFiles = Set(library.compactMap(\.sourceFile))
        let missingFiles = Set(sourceFiles).subtracting(parsedFiles)
        #expect(
            missingFiles.isEmpty,
            "Unparsed blocks: \(missingFiles.sorted().joined(separator: ", "))"
        )
    }

    @Test func invalidatesDirectoryCacheWhenABlockFileChanges() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let blockURL = directory.appending(path: "cache_test.js")
        try """
        module.exports = {
            name: "Before",
            category: "Tests",
            inputs: [],
            options: [],
            outputs: []
        }
        """.write(to: blockURL, atomically: true, encoding: .utf8)

        let parser = BlockParser()
        #expect(try parser.parseDirectory(directory).first?.name == "Before")
        #expect(try parser.parseDirectory(directory).first?.name == "Before")

        try """
        module.exports = {
            name: "After Cache Refresh",
            category: "Tests",
            inputs: [],
            options: [],
            outputs: []
        }
        """.write(to: blockURL, atomically: true, encoding: .utf8)

        #expect(
            try parser.parseDirectory(directory).first?.name
                == "After Cache Refresh"
        )
    }

    @Test func evaluatesDynamicBlockMetadataFromSavedOptions() throws {
        let url = URL(
            fileURLWithPath: "/Volumes/Data/ONT/ValkyriaBot/blocks/send_message_multi.js"
        )
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let interactionReply = try BlockParser().parseFile(
            url,
            optionValues: [
                "type": .string("int_reply"),
                "use-componentsv2": .boolean(false)
            ]
        )

        #expect(interactionReply.inputs.contains { $0.id == "action" })
        #expect(interactionReply.inputs.contains { $0.id == "interaction" })
        #expect(interactionReply.inputs.contains { $0.id == "content" })
        #expect(interactionReply.inputs.contains { $0.id == "embeds" })
        #expect(
            interactionReply.inputs.first { $0.id == "embeds" }?
                .allowsMultipleConnections == true
        )
        #expect(interactionReply.outputs.contains { $0.id == "interaction" })
        #expect(interactionReply.outputs.contains { $0.id == "message" })
        #expect(interactionReply.outputs.contains { $0.id == "action_error" })
        #expect(
            interactionReply.options.first { $0.id == "type" }?
                .choiceOrder?.first == "int_reply"
        )
        #expect(
            interactionReply.options.first { $0.id == "ephemeral" }?
                .type == .checkbox
        )

        let componentsV2Message = try BlockParser().parseFile(
            url,
            optionValues: [
                "type": .string("msg_send"),
                "use-componentsv2": .boolean(true)
            ]
        )

        #expect(componentsV2Message.inputs.contains { $0.id == "channel" })
        #expect(componentsV2Message.inputs.contains { $0.id == "components" })
        #expect(componentsV2Message.inputs.contains { $0.id == "files" })
        #expect(!componentsV2Message.inputs.contains { $0.id == "interaction" })
        #expect(!componentsV2Message.inputs.contains { $0.id == "content" })
        #expect(!componentsV2Message.inputs.contains { $0.id == "embeds" })
        #expect(!componentsV2Message.inputs.contains { $0.id == "poll" })
        #expect(!componentsV2Message.outputs.contains { $0.id == "interaction" })
        #expect(componentsV2Message.outputs.contains { $0.id == "message" })

        let baseDefinition = try BlockParser().parseFile(url)
        let configuredDefinition = BlockParser().configuredDefinition(
            from: baseDefinition,
            at: url,
            optionValues: [
                "type": .string("msg_send"),
                "use-componentsv2": .boolean(true)
            ]
        )
        #expect(configuredDefinition.inputs.contains { $0.id == "channel" })
        #expect(configuredDefinition.inputs.contains { $0.id == "components" })
        #expect(!configuredDefinition.inputs.contains { $0.id == "interaction" })
    }
}
