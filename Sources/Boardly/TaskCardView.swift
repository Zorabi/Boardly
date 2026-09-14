import SwiftUI

struct TaskCardView: View {
    @EnvironmentObject private var store: BoardStore
    let task: BoardTask
    @State private var isHovering = false

    private var isSelected: Bool { store.selectedTaskID == task.id }

    var body: some View {
        Button {
            store.selectedTaskID = task.id
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                projectLabel

                Text(task.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                metadata
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                isSelected
                    ? BoardlyTheme.selectedCard
                    : (isHovering ? BoardlyTheme.cardHover : BoardlyTheme.card)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? BoardlyTheme.selectedBorder : BoardlyTheme.border, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .onDrag {
            NSItemProvider(object: task.id.uuidString as NSString)
        }
        .contextMenu {
            Menu("移动到") {
                ForEach(TaskStatus.allCases) { status in
                    Button {
                        store.moveTask(id: task.id, to: status)
                    } label: {
                        Label(status.title, systemImage: status.systemImage)
                    }
                    .disabled(status == task.status)
                }
            }
        }
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("按下以打开详情。也可拖放到其他列，或使用菜单移动。")
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
                .foregroundStyle(Calendar.current.isDateInToday(dueDate) ? BoardlyTheme.accent : Color.secondary)
            }

            Spacer()

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
