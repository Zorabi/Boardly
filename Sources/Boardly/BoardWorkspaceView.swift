import SwiftUI

struct BoardWorkspaceView: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @State private var isPresentingNewTask = false
    @State private var isInspectorPresented = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            BoardView(searchText: searchText, onCreateTask: { isPresentingNewTask = true })
                .navigationTitle(store.selectedScopeTitle)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索任务")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isPresentingNewTask = true
                } label: {
                    Label("新建任务", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("新建任务 (⌘N)")

                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Label("任务详情", systemImage: "sidebar.right")
                }
                .disabled(store.selectedTaskID == nil)
                .help("显示或隐藏任务详情")
            }
        }
        .inspector(isPresented: $isInspectorPresented) {
            inspectorContent
                .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .sheet(isPresented: $isPresentingNewTask) {
            NewTaskSheet()
                .environmentObject(store)
        }
        .onChange(of: store.selectedTaskID) { _, selectedTaskID in
            guard selectedTaskID != nil else { return }
            if reduceMotion {
                isInspectorPresented = true
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    isInspectorPresented = true
                }
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
