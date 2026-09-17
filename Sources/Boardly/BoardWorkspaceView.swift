import SwiftUI

/// 窗口级 chrome 配置：标题栏透明化并以 Theme 的 toolbar 语义表面作为窗口背景，
/// 与 SwiftUI 的 toolbarBackground 着色互为兜底，消除默认浅灰标题条。
/// 交通灯、窗口拖动、工具栏按钮与搜索框全部保留原生行为。
struct BoardlyWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configureWindow(of: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWindow(of: nsView)
    }

    private func configureWindow(of view: NSView) {
        // makeNSView 时视图尚未挂到窗口，等待下一个主循环再配置。
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.backgroundColor = BoardlyTheme.toolbarNSColor
        }
    }
}

struct BoardWorkspaceView: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @State private var newTaskContext: NewTaskContext?
    @State private var isInspectorPresented = false
    @State private var isSettingsPresented = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// 携带目标列的新建任务上下文：从工具栏进入默认首列，从列头进入则预填该列。
    struct NewTaskContext: Identifiable {
        let columnID: BoardColumn.ID?
        var id: String { columnID?.uuidString ?? "default" }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            BoardView(searchText: searchText) { columnID in
                newTaskContext = NewTaskContext(columnID: columnID)
            }
            .navigationTitle(store.selectedScopeTitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    settingsButton
                }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索任务")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    newTaskContext = NewTaskContext(columnID: nil)
                } label: {
                    Label("新建任务", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("新建任务 (⌘N)")
            }
        }
        .inspector(isPresented: $isInspectorPresented) {
            inspectorContent
                .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .sheet(item: $newTaskContext) { context in
            NewTaskSheet(initialColumnID: context.columnID)
                .environmentObject(store)
        }
        .onChange(of: store.selectedTaskID) { _, selectedTaskID in
            guard selectedTaskID != nil else { return }
            isSettingsPresented = false
            presentInspector()
        }
    }

    private var settingsIsOpen: Bool {
        isSettingsPresented && isInspectorPresented
    }

    /// 全局设置入口固定在标题栏右侧，避免在看板内容区占用一整行。
    /// 保留文字、图标和状态色，确保它既容易发现，也能明确表达开关状态。
    private var settingsButton: some View {
        Button(action: toggleSettings) {
            Label(
                settingsIsOpen ? "关闭设置" : "设置",
                systemImage: settingsIsOpen ? "gearshape.fill" : "gearshape"
            )
            .boardlyFont(.subheadline, weight: .medium)
            .foregroundStyle(settingsIsOpen ? BoardlyTheme.accent : Color.primary)
            .padding(.horizontal, 10)
            .frame(minWidth: 44, minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(settingsIsOpen ? BoardlyTheme.accent.opacity(0.16) : Color.white.opacity(0.06))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(settingsIsOpen ? BoardlyTheme.accent.opacity(0.45) : BoardlyTheme.border)
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut("i", modifiers: [.command, .option])
        .help(settingsIsOpen ? "关闭看板设置 (⌥⌘I)" : "打开看板设置 (⌥⌘I)")
        .accessibilityLabel(settingsIsOpen ? "关闭看板设置" : "打开看板设置")
        .accessibilityValue(settingsIsOpen ? "已打开" : "已关闭")
    }

    private func toggleSettings() {
        if settingsIsOpen {
            closeInspector()
        } else {
            isSettingsPresented = true
            presentInspector()
        }
    }

    private func closeInspector() {
        isSettingsPresented = false
        if reduceMotion {
            isInspectorPresented = false
        } else {
            withAnimation(.easeIn(duration: 0.15)) {
                isInspectorPresented = false
            }
        }
    }

    private func presentInspector() {
        if reduceMotion {
            isInspectorPresented = true
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                isInspectorPresented = true
            }
        }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if isSettingsPresented || store.selectedTaskID == nil {
            BoardlySettingsView(
                onClose: { closeInspector() },
                onBack: store.selectedTaskID == nil ? nil : { isSettingsPresented = false }
            )
        } else if let selectedTask = store.task(withID: store.selectedTaskID) {
            TaskInspectorView(
                task: Binding(
                    get: { store.task(withID: selectedTask.id) ?? selectedTask },
                    set: { updatedTask in
                        store.updateTask(updatedTask)
                    }
                ),
                onClose: { closeInspector() },
                onDelete: {
                    store.deleteTask(id: selectedTask.id)
                    closeInspector()
                }
            )
        } else {
            ContentUnavailableView(
                "未选择任务",
                systemImage: "rectangle.and.hand.point.up.left",
                description: Text("在看板中选择一张卡片以查看详情。")
            )
        }
    }
}
