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
    static var defaultValue: [TaskStatus: CGRect] { [:] }

    static func reduce(value: inout [TaskStatus: CGRect], nextValue: () -> [TaskStatus: CGRect]) {
        for (status, frame) in nextValue() where value[status] == nil {
            value[status] = frame
        }
    }
}

struct BoardView: View {
    @EnvironmentObject private var store: BoardStore
    let searchText: String
    let onCreateTask: (TaskStatus) -> Void

    /// 列实时几何（命名坐标空间），随窗口/布局变化被动更新。
    @State private var columnFrames: [TaskStatus: CGRect] = [:]

    private var visibleTaskCount: Int {
        TaskStatus.allCases.reduce(0) { result, status in
            result + store.tasks(in: status, matching: searchText).count
        }
    }

    private var columnAnchors: [DirectGripPlanner.ColumnAnchor] {
        TaskStatus.allCases.compactMap { status in
            columnFrames[status].map { DirectGripPlanner.ColumnAnchor(status: status, frame: $0) }
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
                        ForEach(TaskStatus.allCases) { status in
                            TaskColumnView(
                                status: status,
                                searchText: searchText,
                                onCreateTask: onCreateTask,
                                columnAnchors: columnAnchors
                            )
                            .frame(width: 280)
                            .containerRelativeFrame(.vertical)
                        }
                    }
                    .padding(16)
                    .coordinateSpace(name: BoardCoordinateSpace.name)
                }
                .scrollIndicators(.visible)
                .background(BoardlyTheme.canvas)
                .onPreferenceChange(BoardColumnFramesPreferenceKey.self) { frames in
                    columnFrames = frames
                }
            }
        }
    }
}

private struct TaskColumnView: View {
    @EnvironmentObject private var store: BoardStore
    let status: TaskStatus
    let searchText: String
    let onCreateTask: (TaskStatus) -> Void
    let columnAnchors: [DirectGripPlanner.ColumnAnchor]
    @State private var isDropTarget = false

    private var tasks: [BoardTask] {
        store.tasks(in: status, matching: searchText)
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
                    value: [status: geo.frame(in: .named(BoardCoordinateSpace.name))]
                )
            }
        )
        // 列级落点：追加到列尾；空列同样生效。列内精确位置由卡片上的 dropDestination 处理。
        .dropDestination(for: TaskDragPayload.self) { payloads, _ in
            TaskDropHandler.handle(payloads, store: store, to: status, before: nil)
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(status.title)列，\(tasks.count)个任务")
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: status.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BoardlyTheme.statusColor(status))
            Text(status.title)
                .font(.subheadline.weight(.semibold))
            Text(tasks.count, format: .number)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.06), in: Capsule())

            Spacer(minLength: 4)

            Button {
                onCreateTask(status)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(BoardlyIconButtonStyle())
            .help("在“\(status.title)”列新建任务")
            .accessibilityLabel("在\(status.title)列新建任务")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
                onCreateTask(status)
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
