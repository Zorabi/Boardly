import SwiftUI

struct BoardView: View {
    @EnvironmentObject private var store: BoardStore
    let searchText: String
    let onCreateTask: (BoardColumn.ID) -> Void

    @State private var isNewColumnPresented = false
    @State private var editingColumn: BoardColumn?
    @State private var deletingColumn: BoardColumn?
    @State private var columnFrames: [BoardColumn.ID: CGRect] = [:]
    @State private var taskFrames: [BoardTask.ID: CGRect] = [:]
    @State private var directlyDraggedTaskID: BoardTask.ID?
    @State private var draggedTask: BoardTask?
    @State private var directDragLocation: CGPoint?

    private func visibleTasksByColumn(for columns: [BoardColumn]) -> [BoardColumn.ID: [BoardTask]] {
        var grouped: [BoardColumn.ID: [BoardTask]] = [:]
        for column in columns {
            grouped[column.id] = store.tasks(in: column.id, matching: searchText)
        }
        return grouped
    }

    var body: some View {
        let orderedColumns = store.orderedColumns
        let tasksByColumn = visibleTasksByColumn(for: orderedColumns)
        Group {
            if tasksByColumn.values.allSatisfy(\.isEmpty), !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack(alignment: .topLeading) {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(orderedColumns) { column in
                                TaskColumnView(
                                    column: column,
                                    tasks: tasksByColumn[column.id] ?? [],
                                    onCreateTask: onCreateTask,
                                    onRename: { editingColumn = column },
                                    onDelete: { deletingColumn = column },
                                    directlyDraggedTaskID: $directlyDraggedTaskID,
                                    directDragLocation: $directDragLocation,
                                    onDirectDragBegan: { draggedTask = $0 },
                                    onDirectDragEnded: handleDirectDragEnded
                                )
                                .frame(width: 280)
                                .containerRelativeFrame(.vertical)
                            }

                            addColumnPanel
                        }
                        .padding(16)
                    }
                    .scrollIndicators(.visible)
                    .boardlyScrollers()
                    .background(BoardlyTheme.canvas)

                    if let draggedTask, let directDragLocation {
                        TaskCardDragPreview(task: draggedTask)
                            .position(directDragLocation)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                            .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
                            .zIndex(100)
                    }
                }
                .coordinateSpace(name: BoardlyTheme.boardCoordinateSpace)
                .onPreferenceChange(BoardlyColumnFramePreferenceKey.self) { columnFrames = $0 }
                .onPreferenceChange(BoardlyTaskFramePreferenceKey.self) { taskFrames = $0 }
                .sheet(isPresented: $isNewColumnPresented) {
                    NewColumnSheet()
                        .environmentObject(store)
                }
                .sheet(item: $editingColumn) { column in
                    ColumnEditorSheet(column: column)
                        .environmentObject(store)
                }
                .sheet(item: $deletingColumn) { column in
                    ColumnDeleteSheet(column: column)
                        .environmentObject(store)
                }
            }
        }
        // 拖动与输入期间只更新必要状态，不让 SwiftUI 为整个看板生成隐式布局动画。
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func handleDirectDragEnded(taskID: BoardTask.ID, location: CGPoint) {
        defer { draggedTask = nil }
        guard let targetColumn = columnFrames
            .filter({ $0.value.contains(location) })
            .sorted(by: { $0.value.minX < $1.value.minX })
            .first?.key else { return }

        let before = taskFrames
            .filter { candidateID, frame in
                candidateID != taskID && columnFrames[targetColumn]?.intersects(frame) == true
            }
            .sorted { lhs, rhs in
                if lhs.value.midY == rhs.value.midY { return lhs.value.minY < rhs.value.minY }
                return lhs.value.midY < rhs.value.midY
            }
            .first(where: { location.y < $0.value.midY })?.key

        _ = TaskDropHandler.handle(
            [TaskDragPayload(taskID: taskID)],
            store: store,
            to: targetColumn,
            before: before
        )
    }

    /// 看板尾部的“新增列”入口：满足“测试中”“验证中”等自定义状态的创建。
    private var addColumnPanel: some View {
        Button {
            isNewColumnPresented = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .boardlySystemFont(size: 18, weight: .medium)
                Text("新增列")
                    .boardlyFont(.caption, weight: .medium)
            }
            .foregroundStyle(.secondary)
            .frame(width: 120, height: 88)
            .background(
                RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusColumn, style: .continuous)
                    .fill(BoardlyTheme.column.opacity(0.5))
            )
            .overlay {
                RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusColumn, style: .continuous)
                    .strokeBorder(BoardlyTheme.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .buttonStyle(BoardlyPlainButtonStyle())
        .help("新增看板列")
        .accessibilityLabel("新增看板列")
        .accessibilityHint("创建自定义状态列，例如“测试中”或“验证中”")
    }
}

private struct TaskColumnView: View {
    @EnvironmentObject private var store: BoardStore
    @EnvironmentObject private var settings: BoardlySettings
    let column: BoardColumn
    let tasks: [BoardTask]
    let onCreateTask: (BoardColumn.ID) -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    @Binding var directlyDraggedTaskID: BoardTask.ID?
    @Binding var directDragLocation: CGPoint?
    let onDirectDragBegan: (BoardTask) -> Void
    let onDirectDragEnded: (BoardTask.ID, CGPoint) -> Void
    @State private var isDropTarget = false

    private var leftNeighbor: BoardColumn? {
        let ordered = store.orderedColumns
        guard let index = ordered.firstIndex(where: { $0.id == column.id }), index > 0 else { return nil }
        return ordered[index - 1]
    }

    private var rightNeighbor: BoardColumn? {
        let ordered = store.orderedColumns
        guard let index = ordered.firstIndex(where: { $0.id == column.id }),
              index + 1 < ordered.count else { return nil }
        return ordered[index + 1]
    }

    var body: some View {
        VStack(spacing: 0) {
            columnHeader
            Divider()
                .overlay(BoardlyTheme.border)

            ScrollView {
                LazyVStack(spacing: settings.cardDensity.taskSpacing) {
                    if tasks.isEmpty {
                        emptyState
                    } else {
                        ForEach(tasks) { task in
                            TaskCardView(
                                task: task,
                                directlyDraggedTaskID: $directlyDraggedTaskID,
                                directDragLocation: $directDragLocation,
                                onDirectDragBegan: onDirectDragBegan,
                                onDirectDragEnded: onDirectDragEnded
                            )
                        }
                    }
                }
                .padding(10)
            }
            .boardlyScrollers()
        }
        .background(BoardlyTheme.column)
        // 只有本地拖动会读取列 frame；普通滚动和编辑时不再持续向顶层回传几何状态。
        .background {
            if directlyDraggedTaskID != nil {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: BoardlyColumnFramePreferenceKey.self,
                        value: [column.id: geometry.frame(in: .named(BoardlyTheme.boardCoordinateSpace))]
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusColumn, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusColumn, style: .continuous)
                .strokeBorder(
                    isDropTarget ? BoardlyTheme.selectedBorder : BoardlyTheme.border,
                    lineWidth: isDropTarget ? 2 : 1
                )
        }
        // 列级落点：追加到列尾；空列同样生效。列内精确位置由卡片上的 onDrop 处理。
        .onDrop(
            of: [BoardlyTheme.taskDragType],
            delegate: TaskCardDropDelegate(
                store: store,
                columnID: column.id,
                before: nil,
                isTargeted: $isDropTarget
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(column.name)列，\(tasks.count)个任务")
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: column.symbol)
                .boardlySystemFont(size: 12, weight: .semibold)
                .foregroundStyle(BoardlyTheme.projectColor(named: column.colorName))
                .accessibilityHidden(true)
            Text(column.name)
                .boardlyFont(.subheadline, weight: .semibold)
            Text(tasks.count, format: .number)
                .boardlyFont(.caption, monospacedDigits: true)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.06), in: Capsule())

            Spacer(minLength: 4)

            Button {
                onCreateTask(column.id)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(BoardlyIconButtonStyle())
            .help("在“\(column.name)”列新建任务")
            .accessibilityLabel("在\(column.name)列新建任务")

            columnMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contextMenu { columnMenuItems }
    }

    /// 列头常显的更多菜单：列位置调整的可见入口，不依赖右键。
    private var columnMenu: some View {
        Menu {
            columnMenuItems
        } label: {
            Image(systemName: "ellipsis")
                .boardlySystemFont(size: 12, weight: .medium)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .help("\(column.name)列操作")
        .accessibilityLabel("\(column.name)列操作")
        .accessibilityHint("重命名、左移、右移或删除这一列")
    }

    @ViewBuilder
    private var columnMenuItems: some View {
        Button(action: onRename) {
            Label("重命名列…", systemImage: "pencil")
        }
        Button {
            store.moveColumn(id: column.id, byOffset: -1)
        } label: {
            Label("左移列", systemImage: "arrow.left")
        }
        .disabled(leftNeighbor == nil)
        Button {
            store.moveColumn(id: column.id, byOffset: 1)
        } label: {
            Label("右移列", systemImage: "arrow.right")
        }
        .disabled(rightNeighbor == nil)
        Divider()
        Button(role: .destructive, action: onDelete) {
            Label("删除列…", systemImage: "trash")
        }
        .disabled(store.columns.count <= 1)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("暂无任务")
                .boardlyFont(.caption, weight: .medium)
                .foregroundStyle(.secondary)
            Text("拖放卡片到这里，或点按右上角 + 新建。")
                .boardlyFont(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button {
                onCreateTask(column.id)
            } label: {
                Label("新建任务", systemImage: "plus")
                    .boardlyFont(.caption, weight: .medium)
            }
            .buttonStyle(BoardlySecondaryButtonStyle())
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .accessibilityElement(children: .combine)
    }
}

struct BoardlyColumnFramePreferenceKey: PreferenceKey {
    static let defaultValue: [BoardColumn.ID: CGRect] = [:]

    static func reduce(value: inout [BoardColumn.ID: CGRect], nextValue: () -> [BoardColumn.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct BoardlyTaskFramePreferenceKey: PreferenceKey {
    static let defaultValue: [BoardTask.ID: CGRect] = [:]

    static func reduce(value: inout [BoardTask.ID: CGRect], nextValue: () -> [BoardTask.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
