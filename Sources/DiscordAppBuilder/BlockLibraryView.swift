import SwiftUI

struct WorkspaceSidebarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            projectHeader
            Divider()

            if state.projectStore == nil {
                ContentUnavailableView(
                    "No project",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Choose a project from the left.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(state.workspaceGroups) { group in
                            WorkspaceCategory(group: group)
                        }
                    }
                    .padding(10)
                }
            }

            Spacer(minLength: 0)
            Divider()
            Text(state.importMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(minWidth: 230, idealWidth: 260, maxWidth: 290)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var projectHeader: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.projectName)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(state.workspaceReferences.count) workspaces")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                state.addCategory()
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.plain)
            .disabled(state.projectStore == nil)
            .help("Add Category")
        }
        .frame(height: 48)
        .padding(.horizontal, 12)
    }
}

private struct WorkspaceCategory: View {
    @EnvironmentObject private var state: AppState
    let group: WorkspaceGroup
    @State private var isDropTargeted = false

    var body: some View {
        DisclosureGroup(isExpanded: expandedBinding) {
            VStack(spacing: 2) {
                ForEach(group.workspaces) { workspace in
                    WorkspaceChannelRow(
                        workspace: workspace,
                        groupID: group.id,
                        isSelected: state.currentWorkspaceID == workspace.id
                    )
                }

                if group.workspaces.isEmpty {
                    Button {
                        state.addWorkspace(to: group.id)
                    } label: {
                        Label("Create workspace", systemImage: "plus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 3)
        } label: {
            HStack(spacing: 5) {
                Text(group.info.title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    state.addWorkspace(to: group.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .help("Add Workspace")
            }
        }
        .contextMenu {
            Button {
                state.addWorkspace(to: group.id)
            } label: {
                Label("Add Workspace", systemImage: "plus")
            }

            Button {
                state.pasteWorkspace(into: group.id)
            } label: {
                Label("Paste Workspace", systemImage: "doc.on.clipboard")
            }
            .disabled(!state.canPasteWorkspace)

            Divider()

            Button {
                state.renameCategory(group.id)
            } label: {
                Label("Rename Category...", systemImage: "pencil")
            }
        }
        .background(
            isDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
        .dropDestination(for: String.self) { workspaceIDs, _ in
            guard let workspaceID = workspaceIDs.first,
                  state.workspaceReferences.contains(where: {
                      $0.workspaceID == workspaceID
                  })
            else { return false }
            state.moveWorkspace(workspaceID, to: group.id)
            return true
        } isTargeted: {
            isDropTargeted = $0
        }
    }

    private var expandedBinding: Binding<Bool> {
        Binding(
            get: { !group.info.collapsed },
            set: { state.setCategory(group.id, expanded: $0) }
        )
    }
}

private struct WorkspaceChannelRow: View {
    @EnvironmentObject private var state: AppState
    let workspace: ProjectWorkspace
    let groupID: String
    let isSelected: Bool

    var body: some View {
        Button {
            state.selectWorkspace(workspace.id)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "number")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 16)
                Text(workspace.info.title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !workspace.active {
                    Image(systemName: "pause.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Inactive workspace")
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 7)
            .background(
                isSelected ? Color.accentColor.opacity(0.16) : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(workspace.id)
        .contextMenu {
            Button {
                state.renameWorkspace(workspace.id)
            } label: {
                Label("Rename Workspace...", systemImage: "pencil")
            }

            Button {
                state.setWorkspaceActive(workspace.id, active: !workspace.active)
            } label: {
                Label(
                    workspace.active ? "Disable Workspace" : "Enable Workspace",
                    systemImage: workspace.active ? "pause.circle" : "play.circle"
                )
            }

            Menu {
                ForEach(state.workspaceGroups.filter { $0.id != groupID }) { category in
                    Button(category.info.title) {
                        state.moveWorkspace(workspace.id, to: category.id)
                    }
                }
            } label: {
                Label("Move to Category", systemImage: "folder")
            }
            .disabled(state.workspaceGroups.count < 2)

            Divider()

            Button {
                state.copyWorkspace(workspace.id)
            } label: {
                Label("Copy Workspace", systemImage: "doc.on.doc")
            }

            Button {
                state.duplicateWorkspace(workspace.id)
            } label: {
                Label("Duplicate Workspace", systemImage: "plus.square.on.square")
            }

            Divider()

            Button(role: .destructive) {
                state.deleteWorkspace(workspace.id)
            } label: {
                Label("Delete Workspace...", systemImage: "trash")
            }
        }
    }
}
