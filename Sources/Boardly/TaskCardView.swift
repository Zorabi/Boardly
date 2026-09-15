import SwiftUI

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
        // 类型安全拖放：Transferable 载荷经 CodableRepresentation 编码为 com.boardly.task，
        // 与所有 dropDestination 的解码端使用同一类型，杜绝传输类型不一致。
        .draggable(TaskDragPayload(taskID: task.id))
        // 拖到卡片上方：插入到这张卡片之前，实现列内重排。
        .dropDestination(for: TaskDragPayload.self) { payloads, _ in
            TaskDropHandler.handle(
                payloads,
                store: store,
                to: task.status,
                before: task.id
            )
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
        .help("拖动卡片可移动到其他列或调整顺序；点按查看详情")
        .contextMenu { moveMenuItems }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("点按打开详情。可从卡片任意区域拖动（左上角抓取指示），或使用移动菜单调整状态。")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { store.selectedTaskID = task.id }
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            dragGrip
            projectLabel
            Spacer(minLength: 6)
            moveMenu
        }
    }

    /// 克制的拖动 affordance：悬停或选中时在卡片左上角浮现抓取指示，
    /// 与右上角 ellipsis 菜单分居两端，互不重叠。
    private var dragGrip: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.tertiary)
            .opacity(isHovering || isSelected ? 1 : 0)
            .accessibilityHidden(true)
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

/// 任务卡片拖放载荷：macOS 14 类型安全 Transferable，经 CodableRepresentation
/// 以稳定 JSON 编码写入 com.boardly.task；拖出与落点两侧由系统保证类型一致。
struct TaskDragPayload: Codable, Hashable, Transferable, Sendable {
    let taskID: BoardTask.ID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: BoardlyTheme.taskDragType)
    }
}

// MARK: - 拖放解析

/// 卡片与列共用的 drop action 抽象：解码后的载荷在此同步应用移动，
/// 不依赖 UI 状态，可被单元测试直接调用验证 store.moveTask 行为。
@MainActor
enum TaskDropHandler {
    /// 返回是否接受本次拖放；拖到自身卡片上返回 false（无操作）。
    static func handle(
        _ payloads: [TaskDragPayload],
        store: BoardStore,
        to status: TaskStatus,
        before destinationID: BoardTask.ID?
    ) -> Bool {
        guard let payload = payloads.first, payload.taskID != destinationID else {
            return false
        }
        store.moveTask(id: payload.taskID, to: status, before: destinationID)
        return true
    }
}
