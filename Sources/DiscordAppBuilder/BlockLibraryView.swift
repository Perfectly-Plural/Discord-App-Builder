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

    var body: some View {
        DisclosureGroup(isExpanded: expandedBinding) {
            VStack(spacing: 2) {
                ForEach(group.workspaces) { workspace in
                    WorkspaceChannelRow(
                        workspace: workspace,
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
            Button("Add Workspace") {
                state.addWorkspace(to: group.id)
            }
            Button("Rename Category...") {
                state.renameCategory(group.id)
            }
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
        .contextMenu {
            Button("Rename Workspace...") {
                state.renameWorkspace(workspace.id)
            }
        }
    }
}
