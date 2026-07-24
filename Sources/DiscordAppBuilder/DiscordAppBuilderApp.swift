import SwiftUI

@main
struct DiscordAppBuilderApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(state)
                .frame(minWidth: 1100, minHeight: 720)
                .preferredColorScheme(state.appearance.colorScheme)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project...") {
                    state.createProject()
                }
                .keyboardShortcut("n")

                Button("Open Project...") {
                    state.openProject()
                }
                .keyboardShortcut("o")
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save Project") {
                    state.saveProjectFromUI()
                }
                .keyboardShortcut("s")
                .disabled(state.projectStore == nil)
            }

            CommandGroup(after: .importExport) {
                Button("Import workspaces.json...") {
                    state.chooseWorkspacesFile()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])

                Button("Import Blocks Folder...") {
                    state.importBlocksFromFolder()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Divider()

                Button("Reveal Project in Finder") {
                    state.revealProjectInFinder()
                }
                .disabled(state.projectStore == nil)
            }

            CommandMenu("Workspace") {
                Button("Add Workspace") {
                    state.addWorkspace()
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(state.projectStore == nil)

                Button("Add Category") {
                    state.addCategory()
                }
                .disabled(state.projectStore == nil)

                Divider()

                ForEach(state.workspaceGroups) { group in
                    Menu(group.info.title) {
                        ForEach(group.workspaces) { workspace in
                            Button(workspace.info.title) {
                                state.selectWorkspace(workspace.id)
                            }
                        }

                        Divider()

                        Button("Add Workspace...") {
                            state.addWorkspace(to: group.id)
                        }
                    }
                }
            }

            CommandMenu("Bot") {
                Button("Update bot.js...") {
                    state.updateBotRuntime()
                }
                .disabled(state.projectStore == nil)
            }

            CommandMenu("Appearance") {
                Picker("Appearance", selection: $state.appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title)
                            .tag(option)
                    }
                }
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    state.cutSelection()
                }
                .keyboardShortcut("x")

                Button("Copy") {
                    state.copySelection()
                }
                .keyboardShortcut("c")

                Button("Paste") {
                    state.pasteSelection()
                }
                .keyboardShortcut("v")

                Button("Select All") {
                    state.selectAll()
                }
                .keyboardShortcut("a")
            }

            CommandGroup(after: .pasteboard) {
                Button("Delete Selection") {
                    state.deleteSelection()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!state.hasSelection)
            }
        }
    }
}
