import SwiftUI

struct MainView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var isWorkspaceDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            ProjectRailView()
            Divider()
            WorkspaceSidebarView()
                .frame(width: 260)
            Divider()
            VStack(spacing: 0) {
                WorkspaceTabBarView()
                Divider()
                WorkflowCanvasView()
                    .clipped()
            }
        }
        .navigationTitle(state.projectName)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    state.createProject()
                } label: {
                    Label("New Project", systemImage: "doc.badge.plus")
                }
                .help("New Project")

                Button {
                    state.openProject()
                } label: {
                    Label("Open Project", systemImage: "folder")
                }
                .help("Open Bot Project")

                Button {
                    state.saveProjectFromUI()
                } label: {
                    Label("Save Project", systemImage: "square.and.arrow.down")
                }
                .disabled(state.projectStore == nil || !state.isDirty)
                .help("Save Project")

                Button {
                    state.importBlocksFromFolder()
                } label: {
                    Label("Import Blocks", systemImage: "shippingbox.and.arrow.backward")
                }
                .help("Import Blocks Folder")

                Button {
                    state.chooseWorkspacesFile()
                } label: {
                    Label("Import Workspaces", systemImage: "square.and.arrow.down.on.square")
                }
                .help("Import workspaces.json")

                Button {
                    state.updateBotRuntime()
                } label: {
                    Label("Update bot.js", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(state.projectStore == nil)
                .help("Replace bot.js with the newest runtime included in this application")

                Menu {
                    Picker("Appearance", selection: $state.appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title)
                                .tag(option)
                        }
                    }
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }
                .help("Choose System, Light, or Dark appearance")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            return state.importWorkspacesFile(url)
        } isTargeted: { targeted in
            isWorkspaceDropTargeted = targeted
        }
        .overlay {
            if isWorkspaceDropTargeted {
                ZStack {
                    Color.accentColor.opacity(0.08)
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                        .padding(8)
                    Label("Drop workspaces.json to import", systemImage: "square.and.arrow.down")
                        .font(.title3.weight(.semibold))
                        .padding(14)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .allowsHitTesting(false)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                try? state.saveProject(silent: true)
            }
        }
    }
}
