import SwiftUI

struct WorkspaceTabBarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                if state.openWorkspaceReferences.isEmpty {
                    Label("Open a workspace from the channel list", systemImage: "number")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                } else {
                    ForEach(state.openWorkspaceReferences) { workspace in
                        WorkspaceTab(
                            workspace: workspace,
                            isSelected: state.currentWorkspaceID == workspace.workspaceID,
                            isDirty: state.workspaceIsDirty(workspace.workspaceID)
                        )
                    }
                }
            }
            .frame(minWidth: 0, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 38)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct WorkspaceTab: View {
    @EnvironmentObject private var state: AppState
    let workspace: WorkspaceReference
    let isSelected: Bool
    let isDirty: Bool

    var body: some View {
        HStack(spacing: 4) {
            Button {
                state.selectWorkspace(workspace.workspaceID)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "number")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    Text(workspace.title)
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    if isDirty {
                        Circle()
                            .fill(Color.primary.opacity(0.7))
                            .frame(width: 6, height: 6)
                            .help("Unsaved changes")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                state.closeWorkspaceTab(workspace.workspaceID)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close Workspace Tab")
        }
        .padding(.leading, 11)
        .padding(.trailing, 7)
        .frame(minWidth: 120, maxWidth: 220, minHeight: 38, maxHeight: 38)
        .background(isSelected ? Color(nsColor: .windowBackgroundColor) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(height: 2)
        }
        .overlay(alignment: .trailing) {
            Divider()
        }
    }
}
