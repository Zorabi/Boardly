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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// 携带目标状态的新建任务上下文：从工具栏进入默认“待办”，从列头进入则预填该列状态。
    struct NewTaskContext: Identifiable {
        let status: TaskStatus
        var id: String { status.rawValue }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            BoardView(searchText: searchText) { status in
                newTaskContext = NewTaskContext(status: status)
            }
            .navigationTitle(store.selectedScopeTitle)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索任务")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    newTaskContext = NewTaskContext(status: .todo)
                } label: {
                    Label("新建任务", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("新建任务 (⌘N)")

                Button {
                    toggleInspector()
                } label: {
                    Label("任务详情", systemImage: "sidebar.right")
                }
                .disabled(store.selectedTaskID == nil)
                .keyboardShortcut("i", modifiers: [.command, .option])
                .help("显示或隐藏任务详情 (⌥⌘I)")
            }
        }
        .inspector(isPresented: $isInspectorPresented) {
            inspectorContent
                .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .sheet(item: $newTaskContext) { context in
            NewTaskSheet(initialStatus: context.status)
                .environmentObject(store)
        }
        .onChange(of: store.selectedTaskID) { _, selectedTaskID in
            guard selectedTaskID != nil else { return }
            presentInspector()
        }
    }

    private func toggleInspector() {
        if isInspectorPresented {
            isInspectorPresented = false
        } else {
            presentInspector()
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
        if let selectedTask = store.task(withID: store.selectedTaskID) {
            TaskInspectorView(
                task: Binding(
                    get: { store.task(withID: selectedTask.id) ?? selectedTask },
                    set: { updatedTask in
                        store.updateTask(updatedTask)
                    }
                ),
                onClose: { isInspectorPresented = false },
                onDelete: {
                    store.deleteTask(id: selectedTask.id)
                    isInspectorPresented = false
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
