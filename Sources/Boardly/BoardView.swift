import SwiftUI

struct BoardView: View {
    @EnvironmentObject private var store: BoardStore
    let searchText: String
    let onCreateTask: (BoardColumn.ID) -> Void

    @State private var isNewColumnPresented = false
    @State private var editingColumn: BoardColumn?
    @State private var deletingColumn: BoardColumn?

    private var visibleTaskCount: Int {
        store.orderedColumns.reduce(0) { result, column in
            result + store.tasks(in: column.id, matching: searchText).count
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
                                onDelete: { deletingColumn = column }
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
                            TaskCardView(task: task)
                        }
                    }
                }
                .padding(10)
            }
            .boardlyScrollers()
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
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
