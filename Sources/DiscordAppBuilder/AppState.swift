import AppKit
import Foundation
import UniformTypeIdentifiers

private struct WorkspaceClipboardPayload: Codable {
    let workspace: ProjectWorkspace
}

@MainActor
final class AppState: ObservableObject {
    private static let workflowPasteboardType = NSPasteboard.PasteboardType(
        "software.perfectlyplural.discord-app-builder.workflow-blocks"
    )
    private static let workspacePasteboardType = NSPasteboard.PasteboardType(
        "software.perfectlyplural.discord-app-builder.workspace"
    )
    private let settingsStore: ApplicationSettingsStore

    @Published var appearance: AppAppearance {
        didSet {
            settingsStore.setAppearance(appearance)
        }
    }
    @Published var library: [BlockDefinition] = []
    @Published var document = WorkflowDocument() {
        didSet {
            graphIndex = WorkflowGraphIndex(document: document)
            if let currentWorkspaceID {
                workspaceDocumentCache[currentWorkspaceID] = document
            }
        }
    }
    private(set) var graphIndex = WorkflowGraphIndex(document: WorkflowDocument())
    @Published var selectedBlockIDs: Set<WorkflowBlock.ID> = []
    @Published var selectedConnectionID: WorkflowConnection.ID?
    @Published var pendingOutput: (blockID: WorkflowBlock.ID, portID: String)?
    @Published var importMessage = "Create a project or open an existing bot project"
    @Published private(set) var projectStore: ProjectStore?
    @Published private(set) var currentWorkspaceID: String?
    @Published private(set) var openWorkspaceIDs: [String] = []
    @Published private(set) var isDirty = false {
        didSet {
            guard let currentWorkspaceID else { return }
            if isDirty {
                dirtyWorkspaceIDs.insert(currentWorkspaceID)
            } else {
                dirtyWorkspaceIDs.remove(currentWorkspaceID)
            }
        }
    }
    @Published private(set) var recentProjects: [RecentProject]
    private var workspaceDocumentCache: [String: WorkflowDocument] = [:]
    private var dirtyWorkspaceIDs: Set<String> = []
    private var pasteCount = 0

    init(settingsStore: ApplicationSettingsStore = ApplicationSettingsStore()) {
        self.settingsStore = settingsStore
        appearance = settingsStore.appearance
        let paths = settingsStore.recentProjectPaths
        recentProjects = paths
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path }
            .reduce(into: [String]()) { result, path in
                if !result.contains(path) {
                    result.append(path)
                }
            }
            .map(RecentProject.init(path:))
    }

    var selectedBlock: WorkflowBlock? {
        document.blocks.first { selectedBlockIDs.contains($0.id) }
    }

    var selectedBlockID: WorkflowBlock.ID? {
        get { selectedBlock?.id }
        set {
            selectedBlockIDs = newValue.map { Set([$0]) } ?? []
            selectedConnectionID = nil
        }
    }

    var hasSelection: Bool {
        !selectedBlockIDs.isEmpty || selectedConnectionID != nil
    }

    var categories: [String] {
        Array(Set(library.map(\.category))).sorted()
    }

    var projectName: String {
        projectStore?.projectURL.lastPathComponent ?? "No Project"
    }

    var projectURL: URL? {
        projectStore?.projectURL
    }

    var workspaceReferences: [WorkspaceReference] {
        projectStore?.workspaceReferences ?? []
    }

    var workspaceGroups: [WorkspaceGroup] {
        projectStore?.groups ?? []
    }

    var openWorkspaceReferences: [WorkspaceReference] {
        openWorkspaceIDs.compactMap { workspaceID in
            workspaceReferences.first { $0.workspaceID == workspaceID }
        }
    }

    func workspaceIsDirty(_ workspaceID: String) -> Bool {
        dirtyWorkspaceIDs.contains(workspaceID)
    }

    var canPasteWorkspace: Bool {
        guard let data = NSPasteboard.general.data(forType: Self.workspacePasteboardType) else {
            return false
        }
        return (try? JSONDecoder().decode(WorkspaceClipboardPayload.self, from: data)) != nil
    }

    func createProject() {
        let panel = NSSavePanel()
        panel.title = "Create Discord Bot Project"
        panel.prompt = "Create Project"
        panel.nameFieldLabel = "Project name:"
        panel.nameFieldStringValue = "My Discord Bot"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path), !contents.isEmpty {
            importMessage = "Choose a new or empty folder for the project"
            return
        }

        do {
            let store = try ProjectStore.createProject(at: url)
            try load(store: store)
            importMessage = "Created \(url.lastPathComponent)"
        } catch {
            importMessage = "Project creation failed: \(error.localizedDescription)"
        }
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.title = "Open Bot Project"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Project"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try saveProject(silent: true)
            let store = try ProjectStore.openProject(at: url)
            try load(store: store)
            importMessage = "Opened \(url.lastPathComponent)"
        } catch {
            importMessage = "Could not open project: \(error.localizedDescription)"
        }
    }

    func openRecentProject(_ project: RecentProject) {
        do {
            try saveProject(silent: true)
            let store = try ProjectStore.openProject(at: project.url)
            try load(store: store)
            importMessage = "Opened \(project.name)"
        } catch {
            importMessage = "Could not open \(project.name): \(error.localizedDescription)"
        }
    }

    func forgetRecentProject(_ project: RecentProject) {
        recentProjects.removeAll { $0.id == project.id }
        persistRecentProjects()
    }

    func chooseWorkspacesFile() {
        let panel = NSOpenPanel()
        panel.title = "Import workspaces.json"
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import Workspaces"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = importWorkspacesFile(url)
    }

    @discardableResult
    func importWorkspacesFile(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "json" else {
            importMessage = "Drop a compatible workspaces.json file"
            return false
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            if projectStore == nil, let projectRoot = inferredProjectRoot(for: url) {
                let store = try ProjectStore.openProject(at: projectRoot)
                try load(store: store)
            } else {
                var store: ProjectStore
                if let projectStore {
                    store = projectStore
                } else {
                    guard let destination = chooseDestinationForImportedProject() else { return false }
                    store = try ProjectStore.createProject(at: destination)
                }
                try store.importWorkspaces(from: url)
                try load(store: store)
            }

            let groupCount = projectStore?.groups.count ?? 0
            let workspaceCount = workspaceReferences.count
            importMessage = "Imported \(groupCount) groups and \(workspaceCount) workspaces from \(url.lastPathComponent)"
            return true
        } catch {
            importMessage = "Workspace import failed: \(error.localizedDescription)"
            return false
        }
    }

    func saveProject(silent: Bool = false) throws {
        guard var store = projectStore else { return }
        try mergeDirtyWorkspaceCache(into: &store)
        try store.save()
        projectStore = store
        dirtyWorkspaceIDs.removeAll()
        isDirty = false
        if !silent {
            importMessage = "Saved \(projectName)"
        }
    }

    func saveProjectFromUI() {
        do {
            try saveProject()
        } catch {
            importMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func updateBotRuntime() {
        guard var store = projectStore else {
            importMessage = "Create or open a project first"
            return
        }

        let alert = NSAlert()
        alert.messageText = "Update bot.js?"
        alert.informativeText = """
        This replaces bot.js with the newest runtime included in this application. \
        The current bot.js will be copied to the project's backups folder first.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try mergeDirtyWorkspaceCache(into: &store)
            try store.save()
            let backupURL = try store.updateBotRuntime()
            projectStore = store
            clearDirtyWorkspaceState()
            if let backupURL {
                importMessage = "Updated bot.js; previous version saved to backups/\(backupURL.lastPathComponent)"
            } else {
                importMessage = "Installed the newest bundled bot.js"
            }
        } catch {
            importMessage = "Could not update bot.js: \(error.localizedDescription)"
        }
    }

    func selectWorkspace(_ workspaceID: String) {
        guard projectStore != nil else { return }
        if workspaceID == currentWorkspaceID {
            if !openWorkspaceIDs.contains(workspaceID) {
                openWorkspaceIDs.append(workspaceID)
            }
            return
        }
        do {
            try loadWorkspace(workspaceID)
            if !openWorkspaceIDs.contains(workspaceID) {
                openWorkspaceIDs.append(workspaceID)
            }
        } catch {
            importMessage = "Could not switch workspace: \(error.localizedDescription)"
        }
    }

    func closeWorkspaceTab(_ workspaceID: String) {
        guard let tabIndex = openWorkspaceIDs.firstIndex(of: workspaceID) else { return }

        do {
            try persistCachedWorkspace(workspaceID)
            openWorkspaceIDs.remove(at: tabIndex)
            workspaceDocumentCache.removeValue(forKey: workspaceID)
            dirtyWorkspaceIDs.remove(workspaceID)

            guard workspaceID == currentWorkspaceID else { return }
            if !openWorkspaceIDs.isEmpty {
                let nextIndex = min(tabIndex, openWorkspaceIDs.count - 1)
                try loadWorkspace(openWorkspaceIDs[nextIndex])
            } else {
                currentWorkspaceID = nil
                document = WorkflowDocument(name: projectName)
                clearSelection()
                pendingOutput = nil
                isDirty = false
            }
        } catch {
            importMessage = "Could not close workspace tab: \(error.localizedDescription)"
        }
    }

    func addWorkspace(to groupID: String? = nil) {
        guard var store = projectStore else {
            importMessage = "Create or open a project first"
            return
        }
        let count = store.workspaceReferences.count + 1
        guard let title = promptForName(
            title: "Create Workspace",
            message: "Workspaces appear as channels inside their category.",
            defaultValue: "workspace-\(count)"
        ) else { return }

        do {
            try mergeDirtyWorkspaceCache(into: &store)
            let reference = store.addWorkspace(named: title, to: groupID)
            try store.save()
            projectStore = store
            clearDirtyWorkspaceState()
            try loadWorkspace(reference.workspaceID)
            if !openWorkspaceIDs.contains(reference.workspaceID) {
                openWorkspaceIDs.append(reference.workspaceID)
            }
            importMessage = "Added \(reference.title)"
        } catch {
            importMessage = "Could not add workspace: \(error.localizedDescription)"
        }
    }

    func addCategory() {
        guard var store = projectStore else {
            importMessage = "Create or open a project first"
            return
        }
        guard let title = promptForName(
            title: "Create Category",
            message: "Categories organize related workspaces like Discord channel categories.",
            defaultValue: "New Category"
        ) else { return }

        do {
            try mergeDirtyWorkspaceCache(into: &store)
            store.addCategory(named: title)
            try store.save()
            projectStore = store
            clearDirtyWorkspaceState()
            importMessage = "Added category \(title)"
        } catch {
            importMessage = "Could not add category: \(error.localizedDescription)"
        }
    }

    func setCategory(_ groupID: String, expanded: Bool) {
        guard var store = projectStore else { return }
        do {
            try mergeDirtyWorkspaceCache(into: &store)
            store.setCategory(groupID, collapsed: !expanded)
            try store.save()
            projectStore = store
            clearDirtyWorkspaceState()
        } catch {
            importMessage = "Could not update category: \(error.localizedDescription)"
        }
    }

    func renameCategory(_ groupID: String) {
        guard var store = projectStore,
              let group = store.groups.first(where: { $0.id == groupID }),
              let title = promptForName(
                title: "Rename Category",
                message: "Choose a new category name.",
                defaultValue: group.info.title
              )
        else { return }

        do {
            try mergeDirtyWorkspaceCache(into: &store)
            store.renameCategory(groupID, to: title)
            try store.save()
            projectStore = store
            clearDirtyWorkspaceState()
        } catch {
            importMessage = "Could not rename category: \(error.localizedDescription)"
        }
    }

    func renameWorkspace(_ workspaceID: String) {
        guard var store = projectStore,
              let reference = store.workspaceReferences.first(where: { $0.workspaceID == workspaceID }),
              let title = promptForName(
                title: "Rename Workspace",
                message: "Choose a new workspace name.",
                defaultValue: reference.title
              )
        else { return }

        do {
            try mergeDirtyWorkspaceCache(into: &store)
            store.renameWorkspace(workspaceID, to: title)
            try store.save()
            projectStore = store
            if currentWorkspaceID == workspaceID {
                document.name = title
            } else if var cached = workspaceDocumentCache[workspaceID] {
                cached.name = title
                workspaceDocumentCache[workspaceID] = cached
            }
            clearDirtyWorkspaceState()
        } catch {
            importMessage = "Could not rename workspace: \(error.localizedDescription)"
        }
    }

    func moveWorkspace(_ workspaceID: String, to groupID: String) {
        guard var store = projectStore else { return }
        do {
            try mergeDirtyWorkspaceCache(into: &store)
            try store.moveWorkspace(workspaceID, to: groupID)
            try store.save()
            projectStore = store
            clearDirtyWorkspaceState()
            let category = store.groups.first(where: { $0.id == groupID })?.info.title
                ?? "category"
            importMessage = "Moved workspace to \(category)"
        } catch {
            importMessage = "Could not move workspace: \(error.localizedDescription)"
        }
    }

    func setWorkspaceActive(_ workspaceID: String, active: Bool) {
        guard var store = projectStore else { return }
        do {
            try mergeDirtyWorkspaceCache(into: &store)
            try store.setWorkspace(workspaceID, active: active)
            try store.save()
            projectStore = store
            clearDirtyWorkspaceState()
            importMessage = active ? "Enabled workspace" : "Disabled workspace"
        } catch {
            importMessage = "Could not update workspace: \(error.localizedDescription)"
        }
    }

    func copyWorkspace(_ workspaceID: String) {
        guard var store = projectStore else { return }
        do {
            try mergeDirtyWorkspaceCache(into: &store)
            guard let workspace = store.workspace(withID: workspaceID) else {
                throw ProjectStoreError.workspaceNotFound
            }
            let payload = WorkspaceClipboardPayload(workspace: workspace)
            let data = try JSONEncoder().encode(payload)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(data, forType: Self.workspacePasteboardType)
            pasteboard.setString(workspace.info.title, forType: .string)
            importMessage = "Copied workspace \(workspace.info.title)"
        } catch {
            importMessage = "Could not copy workspace: \(error.localizedDescription)"
        }
    }

    func pasteWorkspace(into groupID: String) {
        guard let data = NSPasteboard.general.data(forType: Self.workspacePasteboardType),
              let payload = try? JSONDecoder().decode(
                  WorkspaceClipboardPayload.self,
                  from: data
              ),
              var store = projectStore
        else {
            importMessage = "No workspace is available to paste"
            return
        }

        do {
            try mergeDirtyWorkspaceCache(into: &store)
            let reference = try store.insertWorkspaceCopy(
                payload.workspace,
                into: groupID
            )
            try store.save()
            projectStore = store
            clearDirtyWorkspaceState()
            try loadWorkspace(reference.workspaceID)
            if !openWorkspaceIDs.contains(reference.workspaceID) {
                openWorkspaceIDs.append(reference.workspaceID)
            }
            importMessage = "Pasted \(reference.title)"
        } catch {
            importMessage = "Could not paste workspace: \(error.localizedDescription)"
        }
    }

    func duplicateWorkspace(_ workspaceID: String) {
        guard var store = projectStore else { return }
        do {
            try mergeDirtyWorkspaceCache(into: &store)
            guard let workspace = store.workspace(withID: workspaceID) else {
                throw ProjectStoreError.workspaceNotFound
            }
            guard let groupID = store.groupID(containing: workspaceID) else {
                throw ProjectStoreError.categoryNotFound
            }
            let reference = try store.insertWorkspaceCopy(workspace, into: groupID)
            try store.save()
            projectStore = store
            clearDirtyWorkspaceState()
            try loadWorkspace(reference.workspaceID)
            if !openWorkspaceIDs.contains(reference.workspaceID) {
                openWorkspaceIDs.append(reference.workspaceID)
            }
            importMessage = "Duplicated \(workspace.info.title)"
        } catch {
            importMessage = "Could not duplicate workspace: \(error.localizedDescription)"
        }
    }

    func deleteWorkspace(_ workspaceID: String) {
        guard let reference = workspaceReferences.first(where: {
            $0.workspaceID == workspaceID
        }) else { return }

        let alert = NSAlert()
        alert.messageText = "Delete \(reference.title)?"
        alert.informativeText = """
        This permanently removes the workspace and all of its blocks, links, settings, and notes.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        _ = deleteWorkspaceImmediately(workspaceID)
    }

    @discardableResult
    func deleteWorkspaceImmediately(_ workspaceID: String) -> Bool {
        guard var store = projectStore else { return false }
        let wasCurrent = currentWorkspaceID == workspaceID
        let tabIndex = openWorkspaceIDs.firstIndex(of: workspaceID)

        do {
            try mergeDirtyWorkspaceCache(into: &store)
            let deleted = try store.deleteWorkspace(workspaceID)
            try store.save()
            projectStore = store
            clearDirtyWorkspaceState()

            openWorkspaceIDs.removeAll { $0 == workspaceID }
            workspaceDocumentCache.removeValue(forKey: workspaceID)
            dirtyWorkspaceIDs.remove(workspaceID)

            if wasCurrent {
                currentWorkspaceID = nil
                let nextOpenID = tabIndex.flatMap { index in
                    openWorkspaceIDs.isEmpty
                        ? nil
                        : openWorkspaceIDs[min(index, openWorkspaceIDs.count - 1)]
                }
                if let nextWorkspaceID = nextOpenID
                    ?? store.workspaceReferences.first?.workspaceID {
                    try loadWorkspace(nextWorkspaceID)
                    if !openWorkspaceIDs.contains(nextWorkspaceID) {
                        openWorkspaceIDs.append(nextWorkspaceID)
                    }
                } else {
                    document = WorkflowDocument(name: projectName)
                    clearSelection()
                    pendingOutput = nil
                    isDirty = false
                }
            }

            importMessage = "Deleted \(deleted.info.title)"
            return true
        } catch {
            importMessage = "Could not delete workspace: \(error.localizedDescription)"
            return false
        }
    }

    func renameBlockFile(for blockID: WorkflowBlock.ID) {
        guard var store = projectStore,
              let currentWorkspaceID,
              let block = document.blocks.first(where: { $0.id == blockID }),
              let filename = promptForName(
                title: "Rename Block File",
                message: "This renames the .js file and updates every workspace that uses it.",
                defaultValue: "\(block.blockFileName).js"
              )
        else { return }

        do {
            try mergeDirtyWorkspaceCache(into: &store)
            try store.save()
            let newName = try store.renameBlockFile(from: block.blockFileName, to: filename)
            projectStore = store
            clearDirtyWorkspaceState()

            let blocksURL = store.projectURL.appending(path: "blocks", directoryHint: .isDirectory)
            library = try BlockParser().parseDirectory(blocksURL)
            workspaceDocumentCache.removeAll()
            for workspaceID in openWorkspaceIDs {
                workspaceDocumentCache[workspaceID] = try store.document(
                    for: workspaceID,
                    library: library
                )
            }
            try loadWorkspace(currentWorkspaceID)
            importMessage = "Renamed \(block.blockFileName).js to \(newName).js in every workspace"
        } catch {
            importMessage = "Could not rename block file: \(error.localizedDescription)"
        }
    }

    func addBlock(_ definition: BlockDefinition, at position: CGPoint? = nil) {
        guard projectStore != nil, currentWorkspaceID != nil else {
            importMessage = "Open a workspace before adding blocks"
            return
        }
        let offset = CGFloat(document.blocks.count % 6) * 28
        let inputWires = Dictionary(uniqueKeysWithValues: definition.inputs.map {
            (
                $0.id,
                $0.allowsMultipleConnections
                    ? JSONValue.array([])
                    : JSONValue.string(ProjectIdentifier.make())
            )
        })
        let blockFileName = definition.sourceFile.map {
            URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent
        } ?? definition.name
        document.blocks.append(
            WorkflowBlock(
                runtimeBlockID: nextRuntimeBlockID(),
                definition: definition,
                position: position ?? CGPoint(x: 180 + offset, y: 120 + offset),
                optionValues: defaultOptionValues(for: definition),
                inputWireValues: inputWires,
                blockFileName: blockFileName
            )
        )
        if let id = document.blocks.last?.id {
            selectBlock(id)
        }
        isDirty = true
    }

    func selectBlock(_ id: WorkflowBlock.ID, extendingSelection: Bool = false) {
        selectedConnectionID = nil
        if extendingSelection {
            if selectedBlockIDs.contains(id) {
                selectedBlockIDs.remove(id)
            } else {
                selectedBlockIDs.insert(id)
            }
        } else {
            selectedBlockIDs = [id]
        }
    }

    func selectConnection(_ id: WorkflowConnection.ID) {
        selectedBlockIDs.removeAll()
        selectedConnectionID = id
    }

    func clearSelection() {
        selectedBlockIDs.removeAll()
        selectedConnectionID = nil
    }

    func selectAllBlocks() {
        selectedBlockIDs = Set(document.blocks.map(\.id))
        selectedConnectionID = nil
    }

    func setBlockPosition(_ id: WorkflowBlock.ID, to position: CGPoint) {
        guard let index = document.blocks.firstIndex(where: { $0.id == id }),
              !document.blocks[index].isLocked
        else { return }
        document.blocks[index].position = position
        isDirty = true
    }

    func resizeBlock(
        _ id: WorkflowBlock.ID,
        to size: CGSize,
        position: CGPoint
    ) {
        guard let index = document.blocks.firstIndex(where: { $0.id == id }),
              !document.blocks[index].isLocked
        else { return }
        document.blocks[index].width = max(
            WorkflowBlock.minimumEditorWidth,
            size.width
        )
        document.blocks[index].height = max(
            WorkflowBlock.minimumEditorHeight,
            size.height
        )
        document.blocks[index].position = position
        isDirty = true
    }

    func setOption(blockID: WorkflowBlock.ID, optionID: String, value: String) {
        guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        let option = document.blocks[index].definition.options.first { $0.id == optionID }
        if option?.type == .number, let integer = Int(value) {
            document.blocks[index].optionValues[optionID] = .integer(integer)
        } else if option?.type == .number, let number = Double(value) {
            document.blocks[index].optionValues[optionID] = .number(number)
        } else if option?.type == .checkbox {
            document.blocks[index].optionValues[optionID] = .boolean(value == "true")
        } else {
            document.blocks[index].optionValues[optionID] = .string(value)
        }
        refreshDefinition(at: index)
        isDirty = true
    }

    func setBooleanOption(
        blockID: WorkflowBlock.ID,
        optionID: String,
        value: Bool
    ) {
        guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        document.blocks[index].optionValues[optionID] = .boolean(value)
        refreshDefinition(at: index)
        isDirty = true
    }

    func setMultiSelectOption(
        blockID: WorkflowBlock.ID,
        optionID: String,
        choice: String,
        selected: Bool
    ) {
        guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        var values = document.blocks[index].optionValues[optionID]?.wireIDs ?? []
        if selected {
            if !values.contains(choice) {
                values.append(choice)
            }
        } else {
            values.removeAll { $0 == choice }
        }
        document.blocks[index].optionValues[optionID] = .array(
            values.map(JSONValue.string)
        )
        refreshDefinition(at: index)
        isDirty = true
    }

    func beginConnection(from blockID: WorkflowBlock.ID, portID: String) {
        pendingOutput = (blockID, portID)
    }

    func completeConnection(to blockID: WorkflowBlock.ID, portID: String) {
        guard let pendingOutput,
              pendingOutput.blockID != blockID,
              let sourceBlock = document.blocks.first(where: { $0.id == pendingOutput.blockID }),
              let targetIndex = document.blocks.firstIndex(where: { $0.id == blockID }),
              let sourcePort = sourceBlock.definition.outputs.first(where: { $0.id == pendingOutput.portID }),
              let targetPort = document.blocks[targetIndex].definition.inputs.first(where: { $0.id == portID }),
              targetPort.accepts(sourcePort)
        else {
            self.pendingOutput = nil
            return
        }

        let wireID: String
        if targetPort.allowsMultipleConnections {
            let values = document.blocks[targetIndex].inputWireValues[portID]?.wireIDs ?? []
            wireID = ProjectIdentifier.make()
            document.blocks[targetIndex].inputWireValues[portID] = .array(
                (values + [wireID]).map(JSONValue.string)
            )
        } else {
            switch document.blocks[targetIndex].inputWireValues[portID] {
            case .array(let values):
                wireID = ProjectIdentifier.make()
                document.blocks[targetIndex].inputWireValues[portID] = .array(
                    values + [.string(wireID)]
                )
            case .string(let existing):
                wireID = existing
                document.connections.removeAll {
                    $0.toBlockID == blockID && $0.toPortID == portID
                }
            default:
                wireID = ProjectIdentifier.make()
                document.blocks[targetIndex].inputWireValues[portID] = .string(wireID)
            }
        }

        let duplicate = !targetPort.allowsMultipleConnections && document.connections.contains {
            $0.fromBlockID == pendingOutput.blockID &&
            $0.fromPortID == pendingOutput.portID &&
            $0.toBlockID == blockID &&
            $0.toPortID == portID
        }
        if !duplicate {
            document.connections.append(
                WorkflowConnection(
                    wireID: wireID,
                    fromBlockID: pendingOutput.blockID,
                    fromPortID: pendingOutput.portID,
                    toBlockID: blockID,
                    toPortID: portID
                )
            )
            isDirty = true
        }
        self.pendingOutput = nil
    }

    func resolvedValueType(for connection: WorkflowConnection) -> BlockValueType {
        graphIndex.resolvedValueType(for: connection)
    }

    func resolvedValueType(
        blockID: WorkflowBlock.ID,
        portID: String,
        direction: BlockPort.Direction,
        occurrence: Int = 0
    ) -> BlockValueType {
        graphIndex.resolvedValueType(
            for: WorkflowPortEndpoint(
                blockID: blockID,
                portID: portID,
                direction: direction
            ),
            occurrence: occurrence
        )
    }

    func deleteSelection() {
        if let selectedConnectionID {
            removeConnections { $0.id == selectedConnectionID }
            self.selectedConnectionID = nil
            isDirty = true
            return
        }

        guard !selectedBlockIDs.isEmpty else { return }
        let deletedIDs = selectedBlockIDs
        removeConnections {
            deletedIDs.contains($0.fromBlockID) || deletedIDs.contains($0.toBlockID)
        }
        document.blocks.removeAll { deletedIDs.contains($0.id) }
        selectedBlockIDs.removeAll()
        if let pendingOutput, deletedIDs.contains(pendingOutput.blockID) {
            self.pendingOutput = nil
        }
        isDirty = true
    }

    func deleteSelectedBlock() {
        deleteSelection()
    }

    func deleteBlock(_ blockID: WorkflowBlock.ID) {
        guard document.blocks.contains(where: { $0.id == blockID }) else { return }
        removeConnections {
            $0.fromBlockID == blockID || $0.toBlockID == blockID
        }
        document.blocks.removeAll { $0.id == blockID }
        selectedBlockIDs.remove(blockID)
        selectedConnectionID = nil
        if pendingOutput?.blockID == blockID {
            pendingOutput = nil
        }
        isDirty = true
    }

    func copySelection() {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            textView.copy(nil)
            return
        }
        guard let data = encodedSelection() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: Self.workflowPasteboardType)
        pasteCount = 0
        importMessage = selectedBlockIDs.count == 1
            ? "Copied 1 block"
            : "Copied \(selectedBlockIDs.count) blocks"
    }

    func pasteSelection() {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            textView.paste(nil)
            return
        }
        guard let data = NSPasteboard.general.data(forType: Self.workflowPasteboardType) else { return }
        pasteCount += 1
        _ = pasteSelection(
            from: data,
            offset: CGSize(width: CGFloat(pasteCount * 32), height: CGFloat(pasteCount * 32))
        )
    }

    func cutSelection() {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            textView.cut(nil)
            return
        }
        copySelection()
        deleteSelection()
    }

    func selectAll() {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            textView.selectAll(nil)
        } else {
            selectAllBlocks()
        }
    }

    func encodedSelection() -> Data? {
        guard !selectedBlockIDs.isEmpty else { return nil }
        let payload = WorkflowClipboardPayload(
            projectPath: projectURL?.standardizedFileURL.path,
            blocks: document.blocks.filter { selectedBlockIDs.contains($0.id) },
            connections: document.connections.filter {
                selectedBlockIDs.contains($0.fromBlockID) &&
                selectedBlockIDs.contains($0.toBlockID)
            }
        )
        return try? JSONEncoder().encode(payload)
    }

    @discardableResult
    func pasteSelection(from data: Data, offset: CGSize = CGSize(width: 32, height: 32)) -> Bool {
        guard let payload = try? JSONDecoder().decode(WorkflowClipboardPayload.self, from: data),
              !payload.blocks.isEmpty
        else { return false }
        if let sourceProjectPath = payload.projectPath,
           let destinationProjectPath = projectURL?.standardizedFileURL.path,
           sourceProjectPath != destinationProjectPath {
            importMessage = "Blocks can only be pasted into workspaces in the same project"
            return false
        }

        var idMap: [WorkflowBlock.ID: WorkflowBlock.ID] = [:]
        var nextRuntimeSequence = nextRuntimeBlockSequence()
        var pastedBlocks = payload.blocks.map { original in
            var pasted = original
            pasted.id = UUID()
            if let currentWorkspaceID {
                pasted.runtimeBlockID = "\(currentWorkspaceID):\(nextRuntimeSequence)"
                nextRuntimeSequence += 1
            } else {
                pasted.runtimeBlockID = nil
            }
            pasted.position.x += offset.width
            pasted.position.y += offset.height
            pasted.inputWireValues = freshInputValues(for: original)
            idMap[original.id] = pasted.id
            return pasted
        }

        var pastedConnections: [WorkflowConnection] = []
        for original in payload.connections {
            guard let fromBlockID = idMap[original.fromBlockID],
                  let toBlockID = idMap[original.toBlockID],
                  let targetIndex = pastedBlocks.firstIndex(where: { $0.id == toBlockID })
            else { continue }

            let wireID = ProjectIdentifier.make()
            switch pastedBlocks[targetIndex].inputWireValues[original.toPortID] {
            case .array(let values):
                pastedBlocks[targetIndex].inputWireValues[original.toPortID] = .array(
                    values + [.string(wireID)]
                )
            default:
                pastedBlocks[targetIndex].inputWireValues[original.toPortID] = .string(wireID)
            }
            pastedConnections.append(
                WorkflowConnection(
                    wireID: wireID,
                    fromBlockID: fromBlockID,
                    fromPortID: original.fromPortID,
                    toBlockID: toBlockID,
                    toPortID: original.toPortID
                )
            )
        }

        document.blocks.append(contentsOf: pastedBlocks)
        document.connections.append(contentsOf: pastedConnections)
        selectedBlockIDs = Set(pastedBlocks.map(\.id))
        selectedConnectionID = nil
        isDirty = true
        importMessage = pastedBlocks.count == 1
            ? "Pasted 1 block"
            : "Pasted \(pastedBlocks.count) blocks"
        return true
    }

    func importBlocksFromFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import Blocks"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try BlockParser().parseDirectory(url)
            guard !imported.isEmpty else {
                importMessage = "No compatible block files found in \(url.lastPathComponent)"
                return
            }

            var copied = 0
            if let projectURL {
                if var store = projectStore {
                    try mergeDirtyWorkspaceCache(into: &store)
                    try store.save()
                    projectStore = store
                    clearDirtyWorkspaceState()
                }
                let destinationFolder = projectURL.appending(path: "blocks", directoryHint: .isDirectory)
                for definition in imported {
                    guard let sourceFile = definition.sourceFile else { continue }
                    let source = url.appending(path: sourceFile)
                    let destination = destinationFolder.appending(path: sourceFile)
                    if !FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.copyItem(at: source, to: destination)
                        copied += 1
                    }
                }
                library = try BlockParser().parseDirectory(destinationFolder)
                if let store = projectStore {
                    try reloadOpenWorkspaceCache(using: store)
                }
                if let currentWorkspaceID {
                    try loadWorkspace(currentWorkspaceID)
                }
            } else {
                library = imported
            }
            importMessage = projectURL == nil
                ? "Loaded \(imported.count) blocks"
                : "Loaded \(library.count) blocks; copied \(copied) new files into the project"
        } catch {
            importMessage = "Block import failed: \(error.localizedDescription)"
        }
    }

    func revealProjectInFinder() {
        guard let projectURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([projectURL])
    }

    private func mergeDirtyWorkspaceCache(into store: inout ProjectStore) throws {
        for workspaceID in dirtyWorkspaceIDs.sorted() {
            guard let document = workspaceDocumentCache[workspaceID] else { continue }
            try store.update(document: document, workspaceID: workspaceID)
        }
    }

    private func clearDirtyWorkspaceState() {
        dirtyWorkspaceIDs.removeAll()
        isDirty = false
    }

    private func reloadOpenWorkspaceCache(using store: ProjectStore) throws {
        var refreshed: [String: WorkflowDocument] = [:]
        for workspaceID in openWorkspaceIDs {
            refreshed[workspaceID] = try store.document(
                for: workspaceID,
                library: library
            )
        }
        workspaceDocumentCache = refreshed
    }

    private func persistCachedWorkspace(_ workspaceID: String) throws {
        guard dirtyWorkspaceIDs.contains(workspaceID),
              let document = workspaceDocumentCache[workspaceID],
              var store = projectStore
        else { return }

        try store.update(document: document, workspaceID: workspaceID)
        try store.save()
        projectStore = store
        dirtyWorkspaceIDs.remove(workspaceID)
        if currentWorkspaceID == workspaceID {
            isDirty = false
        }
    }

    private func load(store: ProjectStore) throws {
        currentWorkspaceID = nil
        workspaceDocumentCache.removeAll()
        dirtyWorkspaceIDs.removeAll()
        isDirty = false
        projectStore = store
        openWorkspaceIDs = []
        rememberProject(store.projectURL)
        let blocksURL = store.projectURL.appending(path: "blocks", directoryHint: .isDirectory)
        library = (try? BlockParser().parseDirectory(blocksURL)) ?? []
        guard let first = store.workspaceReferences.first else {
            currentWorkspaceID = nil
            document = WorkflowDocument(name: store.projectURL.lastPathComponent)
            return
        }
        try loadWorkspace(first.workspaceID)
        openWorkspaceIDs = [first.workspaceID]
    }

    private func loadWorkspace(_ workspaceID: String) throws {
        guard let store = projectStore else { return }
        let selectedDocument: WorkflowDocument
        if let cached = workspaceDocumentCache[workspaceID] {
            selectedDocument = cached
        } else {
            selectedDocument = try store.document(for: workspaceID, library: library)
        }
        currentWorkspaceID = workspaceID
        document = selectedDocument
        clearSelection()
        pendingOutput = nil
        isDirty = dirtyWorkspaceIDs.contains(workspaceID)
    }

    private func freshInputValues(for block: WorkflowBlock) -> [String: JSONValue] {
        var values = block.inputWireValues.mapValues { value in
            if case .array = value {
                return JSONValue.array([])
            }
            return JSONValue.string(ProjectIdentifier.make())
        }
        for input in block.definition.inputs where values[input.id] == nil {
            values[input.id] = .string(ProjectIdentifier.make())
        }
        return values
    }

    private func refreshDefinition(at blockIndex: Int) {
        guard let projectURL,
              document.blocks.indices.contains(blockIndex)
        else { return }
        let block = document.blocks[blockIndex]
        let sourceURL = projectURL
            .appending(path: "blocks", directoryHint: .isDirectory)
            .appending(path: "\(block.blockFileName).js")
        guard let definition = try? BlockParser().parseFile(
            sourceURL,
            optionValues: block.optionValues
        ) else {
            return
        }

        document.blocks[blockIndex].definition = definition
        for input in definition.inputs
        where document.blocks[blockIndex].inputWireValues[input.id] == nil {
            document.blocks[blockIndex].inputWireValues[input.id] =
                input.allowsMultipleConnections
                ? .array([])
                : .string(ProjectIdentifier.make())
        }
        for option in definition.options
        where document.blocks[blockIndex].optionValues[option.id] == nil {
            document.blocks[blockIndex].optionValues[option.id] =
                defaultOptionValue(for: option)
        }
    }

    private func nextRuntimeBlockID() -> String? {
        guard let currentWorkspaceID else { return nil }
        return "\(currentWorkspaceID):\(nextRuntimeBlockSequence())"
    }

    private func nextRuntimeBlockSequence() -> Int {
        guard let currentWorkspaceID else { return document.blocks.count }
        let prefix = "\(currentWorkspaceID):"
        let highest = document.blocks.compactMap { block -> Int? in
            guard let runtimeBlockID = block.runtimeBlockID,
                  runtimeBlockID.hasPrefix(prefix)
            else { return nil }
            return Int(runtimeBlockID.dropFirst(prefix.count))
        }.max() ?? -1
        return highest + 1
    }

    private func removeConnections(where shouldRemove: (WorkflowConnection) -> Bool) {
        let removed = document.connections.filter(shouldRemove)
        for connection in removed {
            guard let targetIndex = document.blocks.firstIndex(where: { $0.id == connection.toBlockID })
            else { continue }
            switch document.blocks[targetIndex].inputWireValues[connection.toPortID] {
            case .array(let values):
                document.blocks[targetIndex].inputWireValues[connection.toPortID] = .array(
                    values.filter { $0 != .string(connection.wireID) }
                )
            case .string(let wireID) where wireID == connection.wireID:
                document.blocks[targetIndex].inputWireValues[connection.toPortID] = .string(
                    ProjectIdentifier.make()
                )
            default:
                break
            }
        }
        document.connections.removeAll(where: shouldRemove)
    }

    private func rememberProject(_ url: URL) {
        let path = url.standardizedFileURL.path
        recentProjects.removeAll { $0.path == path }
        recentProjects.insert(RecentProject(path: path), at: 0)
        if recentProjects.count > 12 {
            recentProjects.removeLast(recentProjects.count - 12)
        }
        persistRecentProjects()
    }

    private func persistRecentProjects() {
        settingsStore.setRecentProjectPaths(recentProjects.map(\.path))
    }

    private func inferredProjectRoot(for workspaceURL: URL) -> URL? {
        let dataDirectory = workspaceURL.deletingLastPathComponent()
        guard workspaceURL.lastPathComponent.lowercased() == ProjectStore.workspaceFileName,
              dataDirectory.lastPathComponent.lowercased() == "data"
        else {
            return nil
        }
        let projectRoot = dataDirectory.deletingLastPathComponent()
        let blocksURL = projectRoot.appending(path: "blocks", directoryHint: .isDirectory)
        let packageURL = projectRoot.appending(path: "package.json")
        guard FileManager.default.fileExists(atPath: blocksURL.path) ||
              FileManager.default.fileExists(atPath: packageURL.path)
        else {
            return nil
        }
        return projectRoot
    }

    private func chooseDestinationForImportedProject() -> URL? {
        let panel = NSSavePanel()
        panel.title = "Create Project for Imported Workspaces"
        panel.prompt = "Create and Import"
        panel.nameFieldLabel = "Project name:"
        panel.nameFieldStringValue = "Imported Bot Project"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path), !contents.isEmpty {
            importMessage = "Choose a new or empty folder for the imported project"
            return nil
        }
        return url
    }

    private func promptForName(
        title: String,
        message: String,
        defaultValue: String
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(string: defaultValue)
        textField.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func defaultOptionValues(for definition: BlockDefinition) -> [String: JSONValue] {
        Dictionary(uniqueKeysWithValues: definition.options.map { option in
            (option.id, defaultOptionValue(for: option))
        })
    }

    private func defaultOptionValue(for option: BlockOption) -> JSONValue {
        if let defaultValue = option.defaultValue {
            return defaultValue
        }
        switch option.type {
        case .checkbox:
            return .boolean(false)
        case .multiselect:
            return .array([])
        case .number:
            let fallback = option.choiceOrder?.first
                ?? option.choices.keys.sorted().first
                ?? ""
            if let integer = Int(fallback) {
                return .integer(integer)
            }
            if let number = Double(fallback) {
                return .number(number)
            }
            return .string(fallback)
        case .select, .text, .color, .unknown:
            let fallback = option.choiceOrder?.first
                ?? option.choices.keys.sorted().first
                ?? ""
            return .string(fallback)
        }
    }
}
