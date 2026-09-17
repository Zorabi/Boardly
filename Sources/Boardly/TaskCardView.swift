import QuartzCore
import SwiftUI

struct TaskCardView: View {
    @EnvironmentObject private var store: BoardStore
    @EnvironmentObject private var settings: BoardlySettings
    let task: BoardTask
    @Binding var directlyDraggedTaskID: BoardTask.ID?
    @Binding var directDragLocation: CGPoint?
    let onDirectDragEnded: (BoardTask.ID, CGPoint) -> Void

    @State private var isHovering = false
    @State private var isDropTarget = false
    @State private var lastDragUpdateTime: CFTimeInterval = 0

    private var isSelected: Bool { store.selectedTaskID == task.id }
    private var isInDoneColumn: Bool { store.isDoneColumn(task.columnID) }

    var body: some View {
        VStack(alignment: .leading, spacing: settings.cardDensity.cardContentSpacing) {
            headerRow

            Text(task.title)
                .boardlyFont(.body, weight: .medium)
                .foregroundStyle(isInDoneColumn ? Color.secondary : Color.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if settings.showTaskNotes, !task.notes.isEmpty {
                Text(task.notes)
                    .boardlyFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            if settings.showTaskMetadata {
                metadata
            }
        }
        .padding(settings.cardDensity.cardPadding)
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
        .opacity(directlyDraggedTaskID == task.id ? 0.62 : 1)
        .contentShape(RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusCard, style: .continuous))
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: BoardlyTaskFramePreferenceKey.self,
                    value: [task.id: geometry.frame(in: .named(BoardlyTheme.boardCoordinateSpace))]
                )
            }
        }
        .onTapGesture { store.selectedTaskID = task.id }
        .onHover { isHovering = $0 }
        // 整张卡片正文由本地 DragGesture 负责拖动，避免 macOS SwiftUI
        // onDrag 启动 NSDraggingSession 时吞掉短距离移动。使用并行手势，
        // 不让拖动手势抢在点按手势前等待阈值，从而让详情面板立即响应。
        // 列/卡片仍保留 onDrop 作为系统拖放与辅助功能退路。
        .simultaneousGesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .named(BoardlyTheme.boardCoordinateSpace))
                .onChanged { value in
                    let now = CACurrentMediaTime()
                    if directlyDraggedTaskID != task.id {
                        directlyDraggedTaskID = task.id
                        directDragLocation = value.location
                        lastDragUpdateTime = now
                    } else if now - lastDragUpdateTime >= (1.0 / 60.0) {
                        // 手势事件可能高于屏幕刷新率；限制到 60Hz，避免拖动时
                        // 让整个看板在每个触控采样点都重新布局。
                        directDragLocation = value.location
                        lastDragUpdateTime = now
                    }
                }
                .onEnded { value in
                    let sourceID = task.id
                    directlyDraggedTaskID = nil
                    directDragLocation = nil
                    lastDragUpdateTime = 0
                    onDirectDragEnded(sourceID, value.location)
                }
        )
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
                .boardlySystemFont(size: 12, weight: .medium)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .focusEffectDisabled()
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
                    .boardlyFont(.caption, weight: .medium)
                    .foregroundStyle(.secondary)
            }
        } else {
            Label("未分类", systemImage: "tray")
                .boardlyFont(.caption, weight: .medium)
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
        .boardlyFont(.caption)
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

/// 本地 DragGesture 的跟手预览。它不参与命中测试，也不带菜单/拖放手势，
/// 只负责让用户在拖动过程中看到正在移动的卡片内容。
struct TaskCardDragPreview: View {
    @EnvironmentObject private var store: BoardStore
    @EnvironmentObject private var settings: BoardlySettings
    let task: BoardTask

    var body: some View {
        VStack(alignment: .leading, spacing: settings.cardDensity.cardContentSpacing) {
            if let project = store.project(withID: task.projectID) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(BoardlyTheme.projectColor(named: project.colorName))
                        .frame(width: 7, height: 7)
                    Text(project.name)
                        .boardlyFont(.caption, weight: .medium)
                        .foregroundStyle(.secondary)
                }
            }

            Text(task.title)
                .boardlyFont(.body, weight: .medium)
                .foregroundStyle(.primary)
                .lineLimit(2)

            if settings.showTaskNotes, !task.notes.isEmpty {
                Text(task.notes)
                    .boardlyFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(settings.cardDensity.cardPadding)
        .frame(width: 260, alignment: .leading)
        .background(BoardlyTheme.card.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusCard, style: .continuous)
                .strokeBorder(BoardlyTheme.accent, lineWidth: 2)
        }
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
