import SwiftUI
import UniformTypeIdentifiers

struct TaskCardView: View {
    @EnvironmentObject private var store: BoardStore
    let task: BoardTask

    @State private var isHovering = false
    @State private var isDropTarget = false

    private var isSelected: Bool { store.selectedTaskID == task.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow

            Text(task.title)
                .font(.body.weight(.medium))
                .foregroundStyle(task.status == .done ? Color.secondary : Color.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if !task.notes.isEmpty {
                Text(task.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            metadata
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected
                ? BoardlyTheme.selectedCard
                : (isHovering ? BoardlyTheme.cardHover : BoardlyTheme.card)
        )
        .clipShape(RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusCard, style: .continuous)
                .strokeBorder(
                    isDropTarget
                        ? BoardlyTheme.selectedBorder
                        : (isSelected ? BoardlyTheme.selectedBorder.opacity(0.7) : BoardlyTheme.border),
                    lineWidth: isDropTarget ? 2 : 1
                )
        }
        .overlay(alignment: .top) {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(BoardlyTheme.accent)
                    .frame(height: 3)
                    .padding(.horizontal, 10)
                    .padding(.top, -2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusCard, style: .continuous))
        .onTapGesture { store.selectedTaskID = task.id }
        .onHover { isHovering = $0 }
        .onDrag {
            TaskDragPayload.makeProvider(taskID: task.id)
        }
        // 拖到卡片上方：插入到这张卡片之前，实现列内重排。
        .onDrop(of: [BoardlyTheme.taskDragType], isTargeted: $isDropTarget) { providers in
            TaskDropHandler.apply(
                providers,
                store: store,
                to: task.status,
                before: task.id
            )
        }
        .contextMenu { moveMenuItems }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("点按打开详情。可拖放到其他列，或使用移动菜单调整状态。")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { store.selectedTaskID = task.id }
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            projectLabel
            Spacer(minLength: 6)
            moveMenu
        }
    }

    /// 无需拖放的状态移动菜单：满足键盘、VoiceOver 与触控板之外的可靠退路。
    private var moveMenu: some View {
        Menu {
            moveMenuItems
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("移动任务菜单")
        .accessibilityHint("打开后可将任务移动到任意状态，无需拖放。")
    }

    @ViewBuilder
    private var moveMenuItems: some View {
        Section("移动到") {
            ForEach(TaskStatus.allCases) { status in
                Button {
                    store.moveTask(id: task.id, to: status)
                } label: {
                    Label(status.title, systemImage: status.systemImage)
                }
                .disabled(status == task.status)
            }
        }
        Button(role: .destructive) {
            store.deleteTask(id: task.id)
        } label: {
            Label("删除任务", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var projectLabel: some View {
        if let project = store.project(withID: task.projectID) {
            HStack(spacing: 6) {
                Circle()
                    .fill(BoardlyTheme.projectColor(named: project.colorName))
                    .frame(width: 7, height: 7)
                Text(project.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        } else {
            Label("收件箱", systemImage: "tray")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var metadata: some View {
        HStack(spacing: 10) {
            Label(task.priority.title, systemImage: task.priority.systemImage)
                .foregroundStyle(task.priority == .high ? BoardlyTheme.accent : Color.secondary)

            if let dueDate = task.dueDate {
                Label {
                    Text(dueDate, format: .dateTime.month().day())
                } icon: {
                    Image(systemName: "calendar")
                }
                .foregroundStyle(
                    Calendar.current.isDateInToday(dueDate) || (dueDate < .now && task.status != .done)
                        ? BoardlyTheme.statusColor(.inProgress)
                        : Color.secondary
                )
            }

            Spacer(minLength: 0)

            if !task.tags.isEmpty {
                Image(systemName: "tag")
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("\(task.tags.count) 个标签")
            }
        }
        .font(.caption)
    }

    private var accessibilitySummary: String {
        var parts = [task.title, "状态：\(task.status.title)", "优先级：\(task.priority.title)"]
        if let project = store.project(withID: task.projectID) { parts.append("项目：\(project.name)") }
        if let dueDate = task.dueDate {
            parts.append("截止日期：\(dueDate.formatted(date: .long, time: .omitted))")
        }
        return parts.joined(separator: "，")
    }
}

// MARK: - 拖放载荷

/// 任务卡片拖放载荷：编码契约固定为任务 ID 字符串的 UTF-8 `Data`，
/// 注册与读取必须成对使用这里的 helper，禁止绕过契约直接包装 NSString。
enum TaskDragPayload {
    static func makeProvider(taskID: BoardTask.ID) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: BoardlyTheme.taskDragType.identifier,
            visibility: .all
        ) { completion in
            completion(taskID.uuidString.data(using: .utf8), nil)
            return nil
        }
        return provider
    }

    static func decodeTaskID(from provider: NSItemProvider) async throws -> BoardTask.ID? {
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(
                forTypeIdentifier: BoardlyTheme.taskDragType.identifier
            ) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data ?? Data())
                }
            }
        }
        guard let string = String(data: data, encoding: .utf8) else { return nil }
        return UUID(uuidString: string)
    }
}

// MARK: - 拖放解析

/// 列与卡片共用的拖放落地逻辑：解析任务 ID 后在主线程应用移动。
enum TaskDropHandler {
    @MainActor
    static func apply(
        _ providers: [NSItemProvider],
        store: BoardStore,
        to status: TaskStatus,
        before destinationID: BoardTask.ID?
    ) -> Bool {
        let identifier = BoardlyTheme.taskDragType.identifier
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(identifier) }) else {
            return false
        }

        Task { @MainActor in
            guard let taskID = try? await TaskDragPayload.decodeTaskID(from: provider),
                  taskID != destinationID else { return }
            store.moveTask(id: taskID, to: status, before: destinationID)
        }
        return true
    }
}
