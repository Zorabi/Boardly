import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: BoardStore
    @State private var isPresentingNewProject = false
    @State private var editingProject: Project?
    @State private var projectPendingDeletion: Project?
    @State private var isShowingPersistenceSuccess = false
    @State private var persistenceSuccessDismissal: Task<Void, Never>?

    var body: some View {
        let counts = sidebarCounts
        List(selection: $store.selectedScope) {
            Section("任务") {
                SidebarRow(title: "未分类", systemImage: "tray", count: counts.inbox)
                    .tag(SidebarScope.inbox)
                SidebarRow(title: "今天", systemImage: "sun.max", count: counts.today)
                    .tag(SidebarScope.today)
                SidebarRow(title: "所有任务", systemImage: "rectangle.stack", count: store.tasks.count)
                    .tag(SidebarScope.all)
            }

            Section("项目") {
                ForEach(store.projects) { project in
                    projectRow(project, count: counts.projects[project.id, default: 0])
                }

                Button {
                    isPresentingNewProject = true
                } label: {
                    Label("新建项目", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(BoardlyPlainButtonStyle())
                .accessibilityHint("打开新建项目表单")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(BoardlyTheme.sidebar)
        .navigationTitle("Boardly")
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                if store.isPersistencePending {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("正在保存…")
                } else if let persistenceError = store.persistenceError {
                    Image(systemName: "exclamationmark.triangle")
                    Text("保存不可用")
                        .help(persistenceError)
                } else if isShowingPersistenceSuccess {
                    Image(systemName: "checkmark.seal")
                    Text("所有更改已保存")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 16)
            .boardlyFont(.caption)
            .foregroundStyle(store.persistenceError == nil ? Color.secondary : BoardlyTheme.danger)
            .padding(.vertical, 8)
        }
        .onChange(of: store.isPersistencePending) { _, isPending in
            if isPending { hidePersistenceSuccess() }
        }
        .onChange(of: store.persistenceSuccessRevision) { _, _ in
            showPersistenceSuccessBriefly()
        }
        .onDisappear {
            persistenceSuccessDismissal?.cancel()
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

    private func projectRow(_ project: Project, count: Int) -> some View {
        HStack(spacing: 6) {
            Label {
                Text(project.name)
            } icon: {
                Image(systemName: project.symbol)
                    .foregroundStyle(BoardlyTheme.projectColor(named: project.colorName))
            }
            Spacer(minLength: 4)
            Text(count, format: .number)
                .boardlyFont(.caption, monospacedDigits: true)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(count) 个任务")
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

    private func showPersistenceSuccessBriefly() {
        persistenceSuccessDismissal?.cancel()
        isShowingPersistenceSuccess = true
        persistenceSuccessDismissal = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            isShowingPersistenceSuccess = false
            persistenceSuccessDismissal = nil
        }
    }

    private func hidePersistenceSuccess() {
        persistenceSuccessDismissal?.cancel()
        persistenceSuccessDismissal = nil
        isShowingPersistenceSuccess = false
    }

    private struct SidebarCounts {
        var inbox = 0
        var today = 0
        var projects: [Project.ID: Int] = [:]
    }

    private var sidebarCounts: SidebarCounts {
        let doneColumns = store.doneColumnIDs
        let calendar = Calendar.current
        let now = Date.now
        var counts = SidebarCounts()
        for task in store.tasks where !doneColumns.contains(task.columnID) {
            if task.projectID == nil {
                counts.inbox += 1
            } else if let projectID = task.projectID {
                counts.projects[projectID, default: 0] += 1
            }
            if let dueDate = task.dueDate, calendar.isDate(dueDate, inSameDayAs: now) {
                counts.today += 1
            }
        }
        return counts
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
                    .boardlyFont(.caption, monospacedDigits: true)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(count) 个任务")
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .accessibilityElement(children: .combine)
    }
}
