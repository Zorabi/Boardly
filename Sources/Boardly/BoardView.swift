import SwiftUI

struct BoardView: View {
    @EnvironmentObject private var store: BoardStore
    let searchText: String
    let onCreateTask: (TaskStatus) -> Void

    private var visibleTaskCount: Int {
        TaskStatus.allCases.reduce(0) { result, status in
            result + store.tasks(in: status, matching: searchText).count
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
                            TaskColumnView(status: status, searchText: searchText, onCreateTask: onCreateTask)
                                .frame(width: 280)
                                .containerRelativeFrame(.vertical)
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.visible)
                .background(BoardlyTheme.canvas)
            }
        }
    }
}

private struct TaskColumnView: View {
    @EnvironmentObject private var store: BoardStore
    let status: TaskStatus
    let searchText: String
    let onCreateTask: (TaskStatus) -> Void
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
                            TaskCardView(task: task)
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
