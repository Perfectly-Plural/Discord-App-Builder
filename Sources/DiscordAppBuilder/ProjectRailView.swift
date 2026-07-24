import SwiftUI

struct ProjectRailView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 10) {
            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(state.recentProjects) { project in
                        projectButton(project)
                    }
                }
                .padding(.vertical, 10)
            }

            Divider()
                .padding(.horizontal, 12)

            railButton(systemImage: "plus", help: "New Project") {
                state.createProject()
            }

            railButton(systemImage: "folder", help: "Open Project") {
                state.openProject()
            }
            .padding(.bottom, 10)
        }
        .frame(width: 72)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func projectButton(_ project: RecentProject) -> some View {
        let isSelected = state.projectURL?.standardizedFileURL.path == project.path
        return Button {
            state.openRecentProject(project)
        } label: {
            HStack(spacing: 5) {
                Capsule()
                    .fill(isSelected ? Color.primary : Color.clear)
                    .frame(width: 4, height: isSelected ? 34 : 8)

                Text(project.initials)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(projectColor(for: project), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(isSelected ? Color.white.opacity(0.8) : Color.clear, lineWidth: 2)
                    }
            }
            .frame(width: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(project.name)
        .contextMenu {
            Button("Open") {
                state.openRecentProject(project)
            }
            Button("Remove from List") {
                state.forgetRecentProject(project)
            }
        }
    }

    private func railButton(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: 46, height: 46)
                .background(Color(nsColor: .controlBackgroundColor), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func projectColor(for project: RecentProject) -> Color {
        let colors: [Color] = [.indigo, .blue, .teal, .green, .orange, .pink, .purple]
        let value = project.path.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return colors[value % colors.count]
    }
}
