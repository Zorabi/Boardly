import SwiftUI
import UniformTypeIdentifiers

struct BoardView: View {
    @EnvironmentObject private var store: BoardStore
    let searchText: String
    let onCreateTask: () -> Void

    private var visibleTaskCount: Int {
        TaskStatus.allCases.reduce(0) { result, status in
            result + store.tasks(in: status, matching: searchText).count
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            boardHeader
            Divider()

            if visibleTaskCount == 0, !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(TaskStatus.allCases) { status in
                            TaskColumnView(status: status, searchText: searchText)
                                .frame(width: 286)
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

    private var boardHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.selectedScopeTitle)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text("\(visibleTaskCount) 个任务 · 拖放卡片即可更新状态")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button(action: onCreateTask) {
                Label("添加任务", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .accessibilityHint("打开新建任务表单")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

private struct TaskColumnView: View {
    @EnvironmentObject private var store: BoardStore
    let status: TaskStatus
    let searchText: String
    @State private var isDropTarget = false

    private var tasks: [BoardTask] {
        store.tasks(in: status, matching: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: status.systemImage)
                    .foregroundStyle(BoardlyTheme.statusColor(status))
                Text(status.title)
                    .font(.headline)
                Text(tasks.count, format: .number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                Spacer()
            }
            .padding(12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 10) {
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
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isDropTarget ? BoardlyTheme.accent : BoardlyTheme.border, lineWidth: isDropTarget ? 2 : 1)
        }
        .onDrop(of: [UTType.plainText], isTargeted: $isDropTarget) { providers in
            guard let provider = providers.first else { return false }
            provider.loadObject(ofClass: NSString.self) { value, _ in
                guard let taskID = UUID(uuidString: value as? String ?? "") else { return }
                Task { @MainActor in
                    store.moveTask(id: taskID, to: status)
                }
            }
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(status.title)列，\(tasks.count)个任务")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: status.systemImage)
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("暂无任务")
                .font(.subheadline.weight(.medium))
            Text("将卡片拖到这里，或从任务菜单移动。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .accessibilityElement(children: .combine)
    }
}
