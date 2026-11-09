import SwiftUI

struct BoardlyOpenSettingsKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var boardlyOpenSettings: (() -> Void)? {
        get { self[BoardlyOpenSettingsKey.self] }
        set { self[BoardlyOpenSettingsKey.self] = newValue }
    }
}

/// 窗口级 chrome 配置：标题栏透明化并以 Theme 的 toolbar 语义表面作为窗口背景，
/// 与 SwiftUI 的 toolbarBackground 着色互为兜底，消除默认浅灰标题条。
/// 交通灯、窗口拖动、工具栏按钮与搜索框全部保留原生行为。
struct BoardlyWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // makeNSView 时视图尚未挂到窗口，等待下一个主循环再配置一次。
        DispatchQueue.main.async { Self.configureWindow(of: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Self.configureWindow(of: nsView)
    }

    private static func configureWindow(of view: NSView) {
        guard let window = view.window else { return }
        if !window.titlebarAppearsTransparent {
            window.titlebarAppearsTransparent = true
        }
        if window.backgroundColor?.isEqual(BoardlyTheme.toolbarNSColor) != true {
            window.backgroundColor = BoardlyTheme.toolbarNSColor
        }
        // searchable 的工具栏输入框由 AppKit 绘制，SwiftUI 的焦点效果修饰器
        // 无法替代其原生焦点环。只关闭搜索框的外圈，保留输入边界与编辑行为。
        for item in window.toolbar?.items ?? [] {
            if let searchItem = item as? NSSearchToolbarItem {
                searchItem.searchField.focusRingType = .none
            }
            if let itemView = item.view {
                configureSearchFields(in: itemView)
            }
        }
    }

    private static func configureSearchFields(in view: NSView) {
        if let searchField = view as? NSSearchField {
            searchField.focusRingType = .none
        }
        for child in view.subviews {
            configureSearchFields(in: child)
        }
    }
}

struct BoardWorkspaceView: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @State private var draggedTask: BoardTask?
    @State private var directDragLocation: CGPoint?
    @State private var dragPreviewSize = CGSize(width: 260, height: 80)
    @State private var sidebarFrames: [SidebarScope: CGRect] = [:]

    private var sidebarDropTarget: SidebarScope? {
        guard draggedTask != nil, let directDragLocation else { return nil }
        return SidebarDropResolver.target(at: directDragLocation, previewSize: dragPreviewSize, frames: sidebarFrames)
    }

    @State private var newTaskContext: NewTaskContext?
    @State private var isInspectorPresented = false
    @State private var isSettingsPresented = false
    @State private var inspectedTaskID: BoardTask.ID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// 携带目标列的新建任务上下文：从工具栏进入默认首列，从列头进入则预填该列。
    struct NewTaskContext: Identifiable {
        let columnID: BoardColumn.ID?
        var id: String { columnID?.uuidString ?? "default" }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(dropTarget: sidebarDropTarget, isDraggingTask: draggedTask != nil)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            BoardView(
                searchText: searchText,
                onCreateTask: { columnID in
                    newTaskContext = NewTaskContext(columnID: columnID)
                },
                draggedTask: $draggedTask,
                onSidebarDrop: { taskID, location in
                    guard let scope = SidebarDropResolver.target(at: location, previewSize: dragPreviewSize, frames: sidebarFrames) else { return false }
                    return store.moveTask(id: taskID, to: scope)
                },
                directDragLocation: $directDragLocation
            )
            .navigationTitle(store.selectedScopeTitle)
            .overlay(alignment: .trailing) {
                floatingInspector
            }
        }
        .overlay(alignment: .topLeading) {
            // 分栏由不同的原生容器承载；使用窗口全局坐标，再转换到预览层，
            // 避免侧边栏宽度和标题栏高度造成鼠标与卡片的偏移。
            GeometryReader { geometry in
                if let draggedTask, let directDragLocation {
                    let origin = geometry.frame(in: .global).origin
                    TaskCardDragPreview(task: draggedTask)
                        .background {
                            GeometryReader { preview in
                                Color.clear.preference(key: TaskDragPreviewSizeKey.self, value: preview.size)
                            }
                        }
                        .opacity(sidebarDropTarget == nil ? 1 : 0.65)
                        .overlay(alignment: .bottom) {
                            if let target = sidebarDropTarget {
                                Label(dropHint(for: target), systemImage: "checkmark.circle.fill")
                                    .boardlyFont(.caption, weight: .semibold)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(BoardlyTheme.accent, in: Capsule())
                                    .foregroundStyle(.white)
                                    .fixedSize()
                                    .offset(y: 32)
                            }
                        }
                        .position(
                            x: directDragLocation.x - origin.x,
                            y: directDragLocation.y - origin.y
                        )
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
                }
            }
            .allowsHitTesting(false)
        }
        .onPreferenceChange(TaskDragPreviewSizeKey.self) { dragPreviewSize = $0 }
        .onPreferenceChange(SidebarDropFramePreferenceKey.self) { sidebarFrames = $0 }
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索任务")
        .toolbar {
            // macOS 会把 primaryAction 放在系统“收回侧边栏”按钮左侧，
            // 让全局设置成为标题栏最左侧的稳定入口。
            ToolbarItem(placement: .primaryAction) {
                settingsButton
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    newTaskContext = NewTaskContext(columnID: nil)
                } label: {
                    Label("新建任务", systemImage: "plus")
                }
                .boardlyControlFocus()
                .keyboardShortcut("n", modifiers: .command)
                .help("新建任务 (⌘N)")
            }
        }
        .sheet(item: $newTaskContext) { context in
            NewTaskSheet(initialColumnID: context.columnID)
                .environmentObject(store)
        }
        .focusedSceneValue(\.boardlyOpenSettings, {
            openSettings()
        })
        .onChange(of: store.selectedTaskID) { _, selectedTaskID in
            guard let selectedTaskID else {
                // 列删除会迁移并清除原列的选中任务；详情检查器也应随之关闭，
                // 避免目标列（尤其是 Backlog）留下误导性的选中高亮。
                if !isSettingsPresented, isInspectorPresented {
                    setInspectorPresented(false)
                }
                return
            }
            inspectedTaskID = selectedTaskID
            isSettingsPresented = false
            presentInspector()
        }
    }

    private func dropHint(for scope: SidebarScope) -> String {
        switch scope {
        case .today: "设为今天"
        case .inbox: "移至未分类"
        case .project(let id): "移至“\(store.projects.first(where: { $0.id == id })?.name ?? "项目")”"
        case .all: ""
        }
    }

    private var settingsIsOpen: Bool {
        isSettingsPresented && isInspectorPresented
    }

    @ViewBuilder
    private var floatingInspector: some View {
        if isInspectorPresented {
            inspectorContent
                .frame(width: 320)
                .frame(maxHeight: .infinity)
                .background(BoardlyTheme.canvas)
                .clipped()
                .shadow(color: .black.opacity(0.24), radius: 16, x: -4, y: 4)
                .transition(reduceMotion ? .identity : .offset(x: 24).combined(with: .opacity))
                .zIndex(1)
        }
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
        }
        .buttonStyle(BoardlyPlainButtonStyle())
        .boardlyControlFocus()
        .keyboardShortcut("i", modifiers: [.command, .option])
        .help(settingsIsOpen ? "关闭看板设置 (⌥⌘I)" : "打开看板设置 (⌘, 或 ⌥⌘I)")
        .accessibilityLabel(settingsIsOpen ? "关闭看板设置" : "打开看板设置")
        .accessibilityValue(settingsIsOpen ? "已打开" : "已关闭")
    }

    private func toggleSettings() {
        if settingsIsOpen {
            closeInspector()
        } else {
            openSettings()
        }
    }

    private func openSettings() {
        guard !settingsIsOpen else { return }
        isSettingsPresented = true
        presentInspector()
    }

    private func closeInspector() {
        setInspectorPresented(false)
        if store.selectedTaskID != nil {
            store.selectedTaskID = nil
        }
    }

    private func setInspectorPresented(_ isPresented: Bool) {
        guard isInspectorPresented != isPresented else { return }
        if reduceMotion {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isInspectorPresented = isPresented
            }
        } else {
            // 仅移动悬浮面板，不改变看板的可用宽度。
            let animation: Animation = isPresented
                ? .easeOut(duration: 0.20)
                : .easeOut(duration: 0.16)
            withAnimation(animation) {
                isInspectorPresented = isPresented
            }
        }
    }

    private func presentInspector() {
        setInspectorPresented(true)
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if isSettingsPresented {
            BoardlySettingsView(
                onClose: { closeInspector() },
                onBack: store.selectedTaskID == nil ? nil : { isSettingsPresented = false }
            )
        } else if let selectedTask = store.task(withID: inspectedTaskID) {
            TaskInspectorView(
                task: selectedTask,
                onSave: { updatedTask in
                    store.saveTask(updatedTask)
                    closeInspector()
                },
                onClose: { closeInspector() },
                onDelete: {
                    store.deleteTask(id: selectedTask.id)
                    closeInspector()
                }
            )
            .id(selectedTask.id)
        } else {
            ContentUnavailableView(
                "未选择任务",
                systemImage: "rectangle.and.hand.point.up.left",
                description: Text("在看板中选择一张卡片以查看详情。")
            )
        }
    }
}

private struct TaskDragPreviewSizeKey: PreferenceKey {
    static let defaultValue = CGSize(width: 260, height: 80)

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// 高亮与释放共用落点规则，卡片接触目标即可接受，无需鼠标进入文字区域。
enum SidebarDropResolver {
    static func target(at point: CGPoint, previewSize: CGSize, frames: [SidebarScope: CGRect]) -> SidebarScope? {
        let preview = CGRect(
            x: point.x - previewSize.width / 2,
            y: point.y - previewSize.height / 2,
            width: previewSize.width,
            height: previewSize.height
        )
        let candidates = frames.filter { scope, frame in
            scope != .all && frame.insetBy(dx: -12, dy: -6).intersects(preview)
        }
        // 多行同时相交时选择离鼠标纵向最近的一行，避免字典遍历顺序影响落点。
        return candidates.min { lhs, rhs in
            let leftDistance = abs(lhs.value.midY - point.y)
            let rightDistance = abs(rhs.value.midY - point.y)
            if leftDistance != rightDistance { return leftDistance < rightDistance }
            return lhs.value.minY < rhs.value.minY
        }?.key
    }
}
