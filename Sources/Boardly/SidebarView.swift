import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: BoardStore
    var dropTarget: SidebarScope? = nil
    var isDraggingTask = false
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
                    .modifier(SidebarDropTarget(scope: .inbox, isTargeted: dropTarget == .inbox, isDraggingTask: isDraggingTask))
                SidebarRow(title: "今天", systemImage: "sun.max", count: counts.today)
                    .tag(SidebarScope.today)
                    .modifier(SidebarDropTarget(scope: .today, isTargeted: dropTarget == .today, isDraggingTask: isDraggingTask))
                SidebarRow(title: "所有任务", systemImage: "rectangle.stack", count: store.tasks.count)
                    .tag(SidebarScope.all)
                    .modifier(SidebarDropTarget(scope: .all, isTargeted: false, isDraggingTask: isDraggingTask))
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
                .boardlyControlFocus()
                .accessibilityHint("打开新建项目表单")
            }
        }
        .listStyle(.sidebar)
        // 保留原生行选择与方向键导航，仅隐藏列表外围的焦点环。
        .focusEffectDisabled()
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
        .contentShape(Rectangle())
        .onTapGesture {
            guard store.selectedScope != .project(project.id) else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                store.selectedScope = .project(project.id)
            }
        }
        .tag(SidebarScope.project(project.id))
        .modifier(SidebarDropTarget(scope: .project(project.id), isTargeted: dropTarget == .project(project.id), isDraggingTask: isDraggingTask))
        .overlay {
            SidebarProjectMenu(
                onRename: { editingProject = project },
                onDelete: { projectPendingDeletion = project }
            )
        }
        .accessibilityAction(named: "重命名项目") { editingProject = project }
        .accessibilityAction(named: "删除项目") { projectPendingDeletion = project }
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

struct SidebarDropFramePreferenceKey: PreferenceKey {
    static let defaultValue: [SidebarScope: CGRect] = [:]

    static func reduce(value: inout [SidebarScope: CGRect], nextValue: () -> [SidebarScope: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct SidebarDropTarget: ViewModifier {
    let scope: SidebarScope
    let isTargeted: Bool
    let isDraggingTask: Bool

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // 只有任务拖动期间需要落点位置，普通点击不回传几何状态。
                if isDraggingTask, scope != .all {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: SidebarDropFramePreferenceKey.self,
                            value: [scope: geometry.frame(in: .global)]
                        )
                    }
                }
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isTargeted ? Color(nsColor: .controlAccentColor).opacity(0.24) : Color.clear)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
            )
            .fontWeight(isTargeted ? .semibold : nil)
            .accessibilityValue(isTargeted ? "松开以放入此处" : "")
    }
}

/// 单独提供原生上下文菜单，避免 NSTableView 为菜单目标绘制行外框。
/// 仅接收右键或 Control 点按，普通点按、拖动、焦点和键盘事件仍交给列表。
private struct SidebarProjectMenu: NSViewRepresentable {
    let onRename: () -> Void
    let onDelete: () -> Void

    func makeNSView(context: Context) -> MenuView { MenuView() }

    func updateNSView(_ view: MenuView, context: Context) {
        view.onRename = onRename
        view.onDelete = onDelete
    }

    final class MenuView: NSView {
        var onRename: (() -> Void)?
        var onDelete: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                  event.type == .rightMouseDown || event.type == .rightMouseUp
                    || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) else { return nil }
            return super.hitTest(point)
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            let menu = NSMenu()
            let rename = NSMenuItem(title: "重命名项目…", action: #selector(renameProject), keyEquivalent: "")
            rename.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
            rename.target = self
            menu.addItem(rename)
            let delete = NSMenuItem(title: "删除项目…", action: #selector(deleteProject), keyEquivalent: "")
            delete.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            delete.target = self
            menu.addItem(delete)
            return menu
        }

        override func rightMouseDown(with event: NSEvent) {
            if let menu = menu(for: event) {
                NSMenu.popUpContextMenu(menu, with: event, for: self)
            }
        }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) {
                rightMouseDown(with: event)
            } else {
                super.mouseDown(with: event)
            }
        }

        @objc private func renameProject() { onRename?() }
        @objc private func deleteProject() { onDelete?() }
    }
}
