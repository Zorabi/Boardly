import SwiftUI

struct TaskCardView: View {
    @EnvironmentObject private var store: BoardStore
    let task: BoardTask

    @State private var isHovering = false
    @State private var isDropTarget = false

    private var isSelected: Bool { store.selectedTaskID == task.id }
    private var isInDoneColumn: Bool { store.isDoneColumn(task.columnID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow

            Text(task.title)
                .font(.body.weight(.medium))
                .foregroundStyle(isInDoneColumn ? Color.secondary : Color.primary)
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
        // 单一拖放路径：整张卡片正文即拖动入口。onDrag 由系统在短距移动后启动
        // NSDraggingSession（拖拽快照跟随指针），点击/滚动仍由系统正常分发；
        // 载荷以稳定 UTType com.boardly.task 的 JSON 数据表示传输。
        .onDrag { taskDragProvider }
        // 拖到卡片上方：插入到这张卡片之前，实现同列重排与跨列精确落点。
        .onDrop(
            of: [BoardlyTheme.taskDragType],
            delegate: TaskCardDropDelegate(
                store: store,
                columnID: task.columnID,
                before: task.id,
                isTargeted: $isDropTarget
            )
        )
        .help("拖动卡片可移动到其他列或调整顺序；点按查看详情")
        .contextMenu { moveMenuItems }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("点按打开详情。可从卡片任意区域拖动移动，或使用移动菜单调整列。")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { store.selectedTaskID = task.id }
    }

    /// 拖拽载荷的 NSItemProvider：按需编码 JSON，避免给每张卡片预生成数据。
    private var taskDragProvider: NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = task.title
        provider.registerDataRepresentation(
            forTypeIdentifier: BoardlyTheme.taskDragType.identifier,
            visibility: .all
        ) { completion in
            completion(try? JSONEncoder().encode(TaskDragPayload(taskID: task.id)), nil)
            return nil
        }
        return provider
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            projectLabel
            Spacer(minLength: 6)
            moveMenu
        }
    }

    /// 无需拖放的列移动菜单：满足键盘、VoiceOver 与触控板之外的可靠退路。
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
        .accessibilityHint("打开后可将任务移动到任意列，无需拖放。")
    }

    @ViewBuilder
    private var moveMenuItems: some View {
        Section("移动到") {
            ForEach(store.orderedColumns) { column in
                Button {
                    store.moveTask(id: task.id, to: column.id)
                } label: {
                    Label(column.name, systemImage: column.symbol)
                }
                .disabled(column.id == task.columnID)
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
            Label("未分类", systemImage: "tray")
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
                    Calendar.current.isDateInToday(dueDate) || (dueDate < .now && !isInDoneColumn)
                        ? BoardlyTheme.projectColor(named: "amber")
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
        var parts = [task.title]
        if let column = store.column(withID: task.columnID) { parts.append("列：\(column.name)") }
        parts.append("优先级：\(task.priority.title)")
        if let project = store.project(withID: task.projectID) { parts.append("项目：\(project.name)") }
        if let dueDate = task.dueDate {
            parts.append("截止日期：\(dueDate.formatted(date: .long, time: .omitted))")
        }
        return parts.joined(separator: "，")
    }
}

// MARK: - 拖放落点代理

/// onDrop 落点代理：卡片与列共用；解码 com.boardly.task 载荷后经
/// TaskDropHandler 同步应用移动。高亮状态经 Binding 回写，
/// 拖动跟随反馈由系统拖拽快照提供。
struct TaskCardDropDelegate: DropDelegate {
    let store: BoardStore
    let columnID: BoardColumn.ID
    /// 插入到该任务之前；nil 追加到目标列末尾（空列投放即此路径）。
    let before: BoardTask.ID?
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let provider = info.itemProviders(for: [BoardlyTheme.taskDragType]).first else {
            return false
        }
        let columnID = self.columnID
        let before = self.before
        provider.loadDataRepresentation(forTypeIdentifier: BoardlyTheme.taskDragType.identifier) { data, _ in
            guard let data,
                  let payload = try? JSONDecoder().decode(TaskDragPayload.self, from: data) else { return }
            Task { @MainActor in
                _ = TaskDropHandler.handle([payload], store: store, to: columnID, before: before)
            }
        }
        return true
    }
}

// MARK: - 拖放载荷

/// 任务卡片拖放载荷：以稳定 UTType com.boardly.task 的 JSON 数据表示传输，
/// onDrag 注册端与 onDrop 解码端共用同一类型，杜绝传输类型不一致。
struct TaskDragPayload: Codable, Hashable, Sendable {
    let taskID: BoardTask.ID
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
        to columnID: BoardColumn.ID,
        before destinationID: BoardTask.ID?
    ) -> Bool {
        guard let payload = payloads.first, payload.taskID != destinationID else {
            return false
        }
        store.moveTask(id: payload.taskID, to: columnID, before: destinationID)
        return true
    }
}
