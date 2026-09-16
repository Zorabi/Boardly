import SwiftUI

/// 看板滚动内容的稳定命名坐标空间：列几何在该空间内采集，
/// 不受窗口缩放、侧栏/Inspector 展开或滚动偏移以外的变换影响。
enum BoardCoordinateSpace {
    static let name = "boardly.board"
}

/// 各列在命名坐标空间中的实时 frame 上报；由 BoardView 汇总后
/// 以纯数据向下传递，读取仅在布局阶段发生，不触发持久化。
struct BoardColumnFramesPreferenceKey: PreferenceKey {
    // computed var 保证 Swift 6 并发安全（无共享可变全局状态）。
    static var defaultValue: [BoardColumn.ID: CGRect] { [:] }

    static func reduce(value: inout [BoardColumn.ID: CGRect], nextValue: () -> [BoardColumn.ID: CGRect]) {
        for (columnID, frame) in nextValue() where value[columnID] == nil {
            value[columnID] = frame
        }
    }
}

struct BoardView: View {
    @EnvironmentObject private var store: BoardStore
    let searchText: String
    let onCreateTask: (BoardColumn.ID) -> Void

    /// 列实时几何（命名坐标空间），随窗口/布局变化被动更新。
    @State private var columnFrames: [BoardColumn.ID: CGRect] = [:]
    @State private var isNewColumnPresented = false
    @State private var editingColumn: BoardColumn?
    @State private var deletingColumn: BoardColumn?

    private var visibleTaskCount: Int {
        store.orderedColumns.reduce(0) { result, column in
            result + store.tasks(in: column.id, matching: searchText).count
        }
    }

    private var columnAnchors: [DirectGripPlanner.ColumnAnchor] {
        store.orderedColumns.compactMap { column in
            columnFrames[column.id].map { DirectGripPlanner.ColumnAnchor(columnID: column.id, frame: $0) }
        }
    }

    var body: some View {
        Group {
            if visibleTaskCount == 0, !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(store.orderedColumns) { column in
                            TaskColumnView(
                                column: column,
                                searchText: searchText,
                                onCreateTask: onCreateTask,
                                onRename: { editingColumn = column },
                                onDelete: { deletingColumn = column },
                                columnAnchors: columnAnchors
                            )
                            .frame(width: 280)
                            .containerRelativeFrame(.vertical)
                        }

                        addColumnPanel
                    }
                    .padding(16)
                    .coordinateSpace(name: BoardCoordinateSpace.name)
                }
                .scrollIndicators(.visible)
                .background(BoardlyTheme.canvas)
                .onPreferenceChange(BoardColumnFramesPreferenceKey.self) { frames in
                    columnFrames = frames
                }
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
    }

    /// 看板尾部的“新增列”入口：满足“测试中”“验证中”等自定义状态的创建。
    private var addColumnPanel: some View {
        Button {
            isNewColumnPresented = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                Text("新增列")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .frame(width: 120)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusColumn, style: .continuous)
                    .fill(BoardlyTheme.column.opacity(0.5))
            )
            .overlay {
                RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusColumn, style: .continuous)
                    .strokeBorder(BoardlyTheme.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("新增看板列")
        .accessibilityHint("创建自定义状态列，例如“测试中”或“验证中”")
    }
}

private struct TaskColumnView: View {
    @EnvironmentObject private var store: BoardStore
    let column: BoardColumn
    let searchText: String
    let onCreateTask: (BoardColumn.ID) -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let columnAnchors: [DirectGripPlanner.ColumnAnchor]
    @State private var isDropTarget = false

    private var tasks: [BoardTask] {
        store.tasks(in: column.id, matching: searchText)
    }

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
                LazyVStack(spacing: 8) {
                    if tasks.isEmpty {
                        emptyState
                    } else {
                        ForEach(tasks) { task in
                            TaskCardView(task: task, columnAnchors: columnAnchors)
                        }
                    }
                }
                .padding(10)
            }
        }
        .background(BoardlyTheme.column)
        .clipShape(RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusColumn, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusColumn, style: .continuous)
                .strokeBorder(
                    isDropTarget ? BoardlyTheme.selectedBorder : BoardlyTheme.border,
                    lineWidth: isDropTarget ? 2 : 1
                )
        }
        // 实时上报本列在命名坐标空间中的 frame（仅在布局阶段读取，无布局回馈）。
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: BoardColumnFramesPreferenceKey.self,
                    value: [column.id: geo.frame(in: .named(BoardCoordinateSpace.name))]
                )
            }
        )
        // 列级落点：追加到列尾；空列同样生效。列内精确位置由卡片上的 dropDestination 处理。
        .dropDestination(for: TaskDragPayload.self) { payloads, _ in
            TaskDropHandler.handle(payloads, store: store, to: column.id, before: nil)
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(column.name)列，\(tasks.count)个任务")
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: column.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BoardlyTheme.projectColor(named: column.colorName))
                .accessibilityHidden(true)
            Text(column.name)
                .font(.subheadline.weight(.semibold))
            Text(tasks.count, format: .number)
                .font(.caption.monospacedDigit())
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contextMenu {
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
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("暂无任务")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text("拖放卡片到这里，或点按右上角 + 新建。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button {
                onCreateTask(column.id)
            } label: {
                Label("新建任务", systemImage: "plus")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(BoardlySecondaryButtonStyle())
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .accessibilityElement(children: .combine)
    }
}
