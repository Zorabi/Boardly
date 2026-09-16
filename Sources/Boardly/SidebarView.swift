import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: BoardStore
    @State private var isPresentingNewProject = false
    @State private var editingProject: Project?
    @State private var projectPendingDeletion: Project?

    var body: some View {
        List(selection: $store.selectedScope) {
            Section("任务") {
                SidebarRow(title: "未分类", systemImage: "tray", count: inboxCount)
                    .tag(SidebarScope.inbox)
                SidebarRow(title: "今天", systemImage: "sun.max", count: todayCount)
                    .tag(SidebarScope.today)
                SidebarRow(title: "所有任务", systemImage: "rectangle.stack", count: store.tasks.count)
                    .tag(SidebarScope.all)
            }

            Section("项目") {
                ForEach(store.projects) { project in
                    projectRow(project)
                }

                Button {
                    isPresentingNewProject = true
                } label: {
                    Label("新建项目", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityHint("打开新建项目表单")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(BoardlyTheme.sidebar)
        .navigationTitle("Boardly")
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal")
                Text("所有更改已保存")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $isPresentingNewProject) {
            NewProjectSheet()
                .environmentObject(store)
        }
        .sheet(item: $editingProject) { project in
            ProjectEditorSheet(project: project)
                .environmentObject(store)
        }
        .confirmationDialog(
            "删除项目“\(projectPendingDeletion?.name ?? "")”？",
            isPresented: deletionConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除项目", role: .destructive) {
                if let project = projectPendingDeletion {
                    store.deleteProject(id: project.id)
                }
                projectPendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                projectPendingDeletion = nil
            }
        } message: {
            Text("项目内的任务不会被删除，会回到未分类。")
        }
    }

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 6) {
            Label {
                Text(project.name)
            } icon: {
                Image(systemName: project.symbol)
                    .foregroundStyle(BoardlyTheme.projectColor(named: project.colorName))
            }
            Spacer(minLength: 4)
            Text(store.taskCount(in: project.id), format: .number)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(store.taskCount(in: project.id)) 个任务")
        }
        .tag(SidebarScope.project(project.id))
        .contextMenu {
            Button {
                editingProject = project
            } label: {
                Label("重命名项目…", systemImage: "pencil")
            }
            Button(role: .destructive) {
                projectPendingDeletion = project
            } label: {
                Label("删除项目…", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("项目：\(project.name)")
        .accessibilityHint("点按查看项目看板；右键或辅助功能菜单可重命名与删除。")
    }

    private var deletionConfirmation: Binding<Bool> {
        Binding(
            get: { projectPendingDeletion != nil },
            set: { presented in
                if !presented { projectPendingDeletion = nil }
            }
        )
    }

    private var inboxCount: Int {
        let doneColumns = store.doneColumnIDs
        return store.tasks.filter { $0.projectID == nil && !doneColumns.contains($0.columnID) }.count
    }

    private var todayCount: Int {
        let doneColumns = store.doneColumnIDs
        return store.tasks.filter { task in
            guard let date = task.dueDate else { return false }
            return Calendar.current.isDateInToday(date) && !doneColumns.contains(task.columnID)
        }.count
    }
}

private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let count: Int

    var body: some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                Text(count, format: .number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(count) 个任务")
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .accessibilityElement(children: .combine)
    }
}
