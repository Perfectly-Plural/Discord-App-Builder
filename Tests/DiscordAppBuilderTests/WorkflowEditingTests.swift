import Foundation
import Testing
@testable import DiscordAppBuilder

@MainActor
struct WorkflowEditingTests {
    @Test func cachesOpenWorkspacesAndFlushesEveryDirtyDocument() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "DiscordAppBuilderWorkspaceCache-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let settingsRoot = root.appending(path: "settings", directoryHint: .isDirectory)
        let suiteName = "DiscordAppBuilderWorkspaceCacheTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        var store = try ProjectStore.createProject(at: root.appending(path: "Bot"))
        let firstWorkspaceID = try #require(store.workspaceReferences.first?.workspaceID)
        let secondWorkspace = store.addWorkspace(named: "Second Workspace")
        try store.save()

        let state = AppState(
            settingsStore: ApplicationSettingsStore(
                applicationSupportDirectory: settingsRoot,
                userDefaults: defaults
            )
        )
        let workspaceFile = store.projectURL
            .appending(path: "data", directoryHint: .isDirectory)
            .appending(path: ProjectStore.workspaceFileName)
        #expect(state.importWorkspacesFile(workspaceFile))

        let definition = try #require(state.library.first)
        state.addBlock(definition, at: CGPoint(x: 100, y: 100))
        #expect(state.document.blocks.count == 1)
        #expect(state.workspaceIsDirty(firstWorkspaceID))

        state.selectWorkspace(secondWorkspace.workspaceID)
        #expect(state.document.blocks.isEmpty)
        state.addBlock(definition, at: CGPoint(x: 200, y: 200))
        #expect(state.workspaceIsDirty(secondWorkspace.workspaceID))

        let beforeSave = try ProjectStore.openProject(at: store.projectURL)
        #expect(
            try beforeSave.document(
                for: firstWorkspaceID,
                library: state.library
            ).blocks.isEmpty
        )
        #expect(
            try beforeSave.document(
                for: secondWorkspace.workspaceID,
                library: state.library
            ).blocks.isEmpty
        )

        state.selectWorkspace(firstWorkspaceID)
        #expect(state.document.blocks.count == 1)
        #expect(state.workspaceIsDirty(firstWorkspaceID))
        #expect(state.workspaceIsDirty(secondWorkspace.workspaceID))

        state.selectWorkspace(secondWorkspace.workspaceID)
        #expect(state.document.blocks.count == 1)
        try state.saveProject(silent: true)

        let afterSave = try ProjectStore.openProject(at: store.projectURL)
        #expect(
            try afterSave.document(
                for: firstWorkspaceID,
                library: state.library
            ).blocks.count == 1
        )
        #expect(
            try afterSave.document(
                for: secondWorkspace.workspaceID,
                library: state.library
            ).blocks.count == 1
        )
        #expect(!state.workspaceIsDirty(firstWorkspaceID))
        #expect(!state.workspaceIsDirty(secondWorkspace.workspaceID))

        state.selectWorkspace(firstWorkspaceID)
        state.addBlock(definition, at: CGPoint(x: 300, y: 300))
        state.selectWorkspace(secondWorkspace.workspaceID)
        state.closeWorkspaceTab(firstWorkspaceID)

        let afterClose = try ProjectStore.openProject(at: store.projectURL)
        #expect(
            try afterClose.document(
                for: firstWorkspaceID,
                library: state.library
            ).blocks.count == 2
        )
        #expect(!state.openWorkspaceIDs.contains(firstWorkspaceID))
    }

    @Test func deletingCurrentWorkspaceCleansCacheAndSelectsAnotherOpenTab() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "DiscordAppBuilderWorkspaceDelete-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let suiteName = "DiscordAppBuilderWorkspaceDeleteTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        var store = try ProjectStore.createProject(at: root.appending(path: "Bot"))
        let firstWorkspaceID = try #require(store.workspaceReferences.first?.workspaceID)
        let secondWorkspace = store.addWorkspace(named: "Second Workspace")
        try store.save()

        let state = AppState(
            settingsStore: ApplicationSettingsStore(
                applicationSupportDirectory: root.appending(path: "settings"),
                userDefaults: defaults
            )
        )
        let workspaceFile = store.projectURL
            .appending(path: "data", directoryHint: .isDirectory)
            .appending(path: ProjectStore.workspaceFileName)
        #expect(state.importWorkspacesFile(workspaceFile))

        state.selectWorkspace(secondWorkspace.workspaceID)
        state.selectWorkspace(firstWorkspaceID)
        state.addBlock(try #require(state.library.first))
        #expect(state.workspaceIsDirty(firstWorkspaceID))

        #expect(state.deleteWorkspaceImmediately(firstWorkspaceID))
        #expect(state.currentWorkspaceID == secondWorkspace.workspaceID)
        #expect(!state.openWorkspaceIDs.contains(firstWorkspaceID))
        #expect(!state.workspaceReferences.contains {
            $0.workspaceID == firstWorkspaceID
        })
        #expect(state.document.name == "Second Workspace")

        let reopened = try ProjectStore.openProject(at: store.projectURL)
        #expect(reopened.workspace(withID: firstWorkspaceID) == nil)
        #expect(reopened.workspace(withID: secondWorkspace.workspaceID) != nil)
    }

    @Test func displaysOnlyTheWorkspaceRelativeBlockID() {
        let block = WorkflowBlock(
            runtimeBlockID: "YNRW6AhSEK:14",
            definition: testDefinition(),
            position: CGPoint(x: 100, y: 100),
            blockFileName: "test"
        )

        #expect(block.displayedBlockID(workspaceID: "YNRW6AhSEK") == "#14")
    }

    @Test func resizesUnlockedBlocksAndKeepsLockedBlocksFixed() {
        let definition = testDefinition()
        let unlocked = WorkflowBlock(
            definition: definition,
            position: CGPoint(x: 200, y: 160),
            blockFileName: "unlocked"
        )
        var locked = WorkflowBlock(
            definition: definition,
            position: CGPoint(x: 500, y: 160),
            blockFileName: "locked"
        )
        locked.isLocked = true

        let state = AppState()
        state.document = WorkflowDocument(
            name: "Resize Test",
            blocks: [unlocked, locked]
        )

        state.resizeBlock(
            unlocked.id,
            to: CGSize(width: 540, height: 360),
            position: CGPoint(x: 320, y: 260)
        )
        state.resizeBlock(
            locked.id,
            to: CGSize(width: 700, height: 500),
            position: CGPoint(x: 600, y: 300)
        )

        #expect(state.document.blocks[0].width == 540)
        #expect(state.document.blocks[0].height == 360)
        #expect(state.document.blocks[0].position == CGPoint(x: 320, y: 260))
        #expect(state.document.blocks[1].width == locked.width)
        #expect(state.document.blocks[1].height == locked.height)
        #expect(state.document.blocks[1].position == locked.position)
        #expect(state.isDirty)
    }

    @Test func copiesSettingsAndOnlyLinksBetweenSelectedBlocks() throws {
        let definition = testDefinition()
        let first = WorkflowBlock(
            definition: definition,
            position: CGPoint(x: 100, y: 100),
            optionValues: ["message": .string("Keep this setting")],
            inputWireValues: ["input": .string("first-input")],
            blockFileName: "test"
        )
        let second = WorkflowBlock(
            definition: definition,
            position: CGPoint(x: 400, y: 100),
            optionValues: ["message": .string("Second setting")],
            inputWireValues: ["input": .string("internal-wire")],
            blockFileName: "test"
        )
        let third = WorkflowBlock(
            definition: definition,
            position: CGPoint(x: 700, y: 100),
            optionValues: ["message": .string("Not copied")],
            inputWireValues: ["input": .string("external-wire")],
            blockFileName: "test"
        )
        let internalLink = WorkflowConnection(
            wireID: "internal-wire",
            fromBlockID: first.id,
            fromPortID: "output",
            toBlockID: second.id,
            toPortID: "input"
        )
        let externalLink = WorkflowConnection(
            wireID: "external-wire",
            fromBlockID: second.id,
            fromPortID: "output",
            toBlockID: third.id,
            toPortID: "input"
        )

        let state = AppState()
        state.document = WorkflowDocument(
            name: "Copy Test",
            blocks: [first, second, third],
            connections: [internalLink, externalLink]
        )
        state.selectBlock(first.id)
        state.selectBlock(second.id, extendingSelection: true)

        let data = try #require(state.encodedSelection())
        #expect(state.pasteSelection(from: data))
        #expect(state.document.blocks.count == 5)
        #expect(state.document.connections.count == 3)
        #expect(state.selectedBlockIDs.count == 2)

        let pastedBlocks = state.document.blocks.filter { state.selectedBlockIDs.contains($0.id) }
        #expect(pastedBlocks.map { $0.optionValues["message"] }.contains(.string("Keep this setting")))
        #expect(pastedBlocks.map { $0.optionValues["message"] }.contains(.string("Second setting")))

        let pastedLinks = state.document.connections.filter {
            state.selectedBlockIDs.contains($0.fromBlockID) ||
            state.selectedBlockIDs.contains($0.toBlockID)
        }
        #expect(pastedLinks.count == 1)
        #expect(state.selectedBlockIDs.contains(pastedLinks[0].fromBlockID))
        #expect(state.selectedBlockIDs.contains(pastedLinks[0].toBlockID))
        #expect(pastedLinks[0].wireID != internalLink.wireID)
    }

    @Test func deletesLinksWithoutDeletingTheirBlocks() {
        let definition = testDefinition()
        let first = WorkflowBlock(
            definition: definition,
            position: CGPoint(x: 100, y: 100),
            inputWireValues: ["input": .string("first-input")],
            blockFileName: "test"
        )
        let second = WorkflowBlock(
            definition: definition,
            position: CGPoint(x: 400, y: 100),
            inputWireValues: ["input": .string("linked-wire")],
            blockFileName: "test"
        )
        let link = WorkflowConnection(
            wireID: "linked-wire",
            fromBlockID: first.id,
            fromPortID: "output",
            toBlockID: second.id,
            toPortID: "input"
        )

        let state = AppState()
        state.document = WorkflowDocument(
            name: "Delete Test",
            blocks: [first, second],
            connections: [link]
        )
        state.selectConnection(link.id)
        state.deleteSelection()

        #expect(state.document.blocks.count == 2)
        #expect(state.document.connections.isEmpty)
        #expect(
            state.document.blocks[1].inputWireValues["input"]?.displayString != link.wireID
        )
    }

    @Test func deletesOneBlockAndItsAttachedLinks() {
        let definition = testDefinition()
        let first = WorkflowBlock(
            definition: definition,
            position: CGPoint(x: 100, y: 100),
            blockFileName: "test"
        )
        let second = WorkflowBlock(
            definition: definition,
            position: CGPoint(x: 400, y: 100),
            inputWireValues: ["input": .string("linked-wire")],
            blockFileName: "test"
        )
        let link = WorkflowConnection(
            wireID: "linked-wire",
            fromBlockID: first.id,
            fromPortID: "output",
            toBlockID: second.id,
            toPortID: "input"
        )
        let state = AppState()
        state.document = WorkflowDocument(
            name: "Middle Click Delete Test",
            blocks: [first, second],
            connections: [link]
        )

        state.deleteBlock(first.id)

        #expect(state.document.blocks.map(\.id) == [second.id])
        #expect(state.document.connections.isEmpty)
        #expect(state.isDirty)
    }

    @Test func connectsCompatibleOutputAndInputPorts() throws {
        let definition = testDefinition()
        let source = WorkflowBlock(
            definition: definition,
            position: CGPoint(x: 100, y: 100),
            blockFileName: "test"
        )
        let target = WorkflowBlock(
            definition: definition,
            position: CGPoint(x: 400, y: 100),
            blockFileName: "test"
        )
        let state = AppState()
        state.document = WorkflowDocument(
            name: "Connection Test",
            blocks: [source, target]
        )

        state.beginConnection(from: source.id, portID: "output")
        state.completeConnection(to: target.id, portID: "input")

        let connection = try #require(state.document.connections.first)
        #expect(connection.fromBlockID == source.id)
        #expect(connection.fromPortID == "output")
        #expect(connection.toBlockID == target.id)
        #expect(connection.toPortID == "input")
        #expect(
            state.document.blocks[1].inputWireValues["input"] == .string(connection.wireID)
        )
        #expect(state.pendingOutput == nil)
    }

    @Test func appendsConnectionsToRepeatableInputPorts() throws {
        var definition = testDefinition()
        definition.inputs[0].allowsMultipleConnections = true
        let firstSource = WorkflowBlock(
            definition: definition,
            position: CGPoint(x: 100, y: 100),
            blockFileName: "test"
        )
        let secondSource = WorkflowBlock(
            definition: definition,
            position: CGPoint(x: 100, y: 300),
            blockFileName: "test"
        )
        let target = WorkflowBlock(
            definition: definition,
            position: CGPoint(x: 500, y: 200),
            blockFileName: "test"
        )
        let state = AppState()
        state.document = WorkflowDocument(
            name: "Repeatable Connection Test",
            blocks: [firstSource, secondSource, target]
        )

        state.beginConnection(from: firstSource.id, portID: "output")
        state.completeConnection(to: target.id, portID: "input")
        state.beginConnection(from: secondSource.id, portID: "output")
        state.completeConnection(to: target.id, portID: "input")

        #expect(state.document.connections.count == 2)
        let wireIDs = state.document.blocks[2].inputWireValues["input"]?.wireIDs ?? []
        #expect(wireIDs.count == 2)
        #expect(Set(wireIDs).count == 2)
        #expect(Set(state.document.connections.map(\.wireID)) == Set(wireIDs))
    }

    @Test func indexesRepeatableConnectionOccurrencesAndResolvedTypes() {
        var sourceDefinition = testDefinition()
        sourceDefinition.outputs[0].types = [.unspecified]
        sourceDefinition.outputs[0].allowsMultipleConnections = true

        var objectTargetDefinition = testDefinition()
        objectTargetDefinition.inputs[0].types = [.object]
        var textTargetDefinition = testDefinition()
        textTargetDefinition.inputs[0].types = [.text]

        let source = WorkflowBlock(
            definition: sourceDefinition,
            position: .zero,
            blockFileName: "source"
        )
        let objectTarget = WorkflowBlock(
            definition: objectTargetDefinition,
            position: .zero,
            blockFileName: "object-target"
        )
        let textTarget = WorkflowBlock(
            definition: textTargetDefinition,
            position: .zero,
            blockFileName: "text-target"
        )
        let objectConnection = WorkflowConnection(
            wireID: "object-wire",
            fromBlockID: source.id,
            fromPortID: "output",
            toBlockID: objectTarget.id,
            toPortID: "input"
        )
        let textConnection = WorkflowConnection(
            wireID: "text-wire",
            fromBlockID: source.id,
            fromPortID: "output",
            toBlockID: textTarget.id,
            toPortID: "input"
        )
        let index = WorkflowGraphIndex(
            document: WorkflowDocument(
                blocks: [source, objectTarget, textTarget],
                connections: [objectConnection, textConnection]
            )
        )
        let outputEndpoint = WorkflowPortEndpoint(
            blockID: source.id,
            portID: "output",
            direction: .output
        )

        #expect(index.connectionCount(for: outputEndpoint) == 2)
        #expect(index.occurrences(for: objectConnection).output == 0)
        #expect(index.occurrences(for: textConnection).output == 1)
        #expect(index.resolvedValueType(for: objectConnection) == .object)
        #expect(index.resolvedValueType(for: textConnection) == .text)
        #expect(
            index.resolvedValueType(for: outputEndpoint, occurrence: 0) == .object
        )
        #expect(
            index.resolvedValueType(for: outputEndpoint, occurrence: 1) == .text
        )
    }

    @Test func resolvesWildcardOutputsFromTheirConnectedInputTypes() {
        let receiverDefinition = BlockDefinition(
            name: "Receiver",
            description: "",
            category: "Tests",
            autoExecute: false,
            inputs: [],
            options: [],
            outputs: [
                BlockPort(
                    id: "objectValue",
                    name: "Object Value",
                    description: "",
                    types: [.unspecified, .text],
                    required: false,
                    direction: .output
                ),
                BlockPort(
                    id: "listValue",
                    name: "List Value",
                    description: "",
                    types: [.unspecified, .text],
                    required: false,
                    direction: .output
                )
            ],
            sourceFile: "receiver.js"
        )
        let consumerDefinition = BlockDefinition(
            name: "Consumer",
            description: "",
            category: "Tests",
            autoExecute: false,
            inputs: [
                BlockPort(
                    id: "object",
                    name: "Object",
                    description: "",
                    types: [.object, .unspecified],
                    required: false,
                    direction: .input
                ),
                BlockPort(
                    id: "list",
                    name: "List",
                    description: "",
                    types: [.list, .unspecified],
                    required: false,
                    direction: .input
                )
            ],
            options: [],
            outputs: [],
            sourceFile: "consumer.js"
        )
        let receiver = WorkflowBlock(
            definition: receiverDefinition,
            position: CGPoint(x: 100, y: 100),
            blockFileName: "receiver"
        )
        let consumer = WorkflowBlock(
            definition: consumerDefinition,
            position: CGPoint(x: 400, y: 100),
            blockFileName: "consumer"
        )
        let objectConnection = WorkflowConnection(
            wireID: "object-wire",
            fromBlockID: receiver.id,
            fromPortID: "objectValue",
            toBlockID: consumer.id,
            toPortID: "object"
        )
        let listConnection = WorkflowConnection(
            wireID: "list-wire",
            fromBlockID: receiver.id,
            fromPortID: "listValue",
            toBlockID: consumer.id,
            toPortID: "list"
        )
        let state = AppState()
        state.document = WorkflowDocument(
            name: "Dynamic Type Test",
            blocks: [receiver, consumer],
            connections: [objectConnection, listConnection]
        )

        #expect(state.resolvedValueType(for: objectConnection) == .object)
        #expect(state.resolvedValueType(for: listConnection) == .list)
        #expect(
            state.resolvedValueType(
                blockID: receiver.id,
                portID: "objectValue",
                direction: .output
            ) == .object
        )
        #expect(
            state.resolvedValueType(
                blockID: receiver.id,
                portID: "listValue",
                direction: .output
            ) == .list
        )
    }

    private func testDefinition() -> BlockDefinition {
        BlockDefinition(
            name: "Test",
            description: "",
            category: "Tests",
            autoExecute: false,
            inputs: [
                BlockPort(
                    id: "input",
                    name: "Input",
                    description: "",
                    types: [.text],
                    required: false,
                    direction: .input
                )
            ],
            options: [
                BlockOption(
                    id: "message",
                    name: "Message",
                    description: "",
                    type: .text,
                    choices: [:]
                )
            ],
            outputs: [
                BlockPort(
                    id: "output",
                    name: "Output",
                    description: "",
                    types: [.text],
                    required: false,
                    direction: .output
                )
            ],
            sourceFile: "test.js"
        )
    }
}
